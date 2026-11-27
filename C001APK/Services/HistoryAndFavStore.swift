import CoolapkKit
import Foundation
import Observation

public struct LocalHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var preview: String
    public var username: String
    public var avatar: String
    public var visitedAt: Date
    public var feed: FeedItem?

    public init(feed: FeedItem, visitedAt: Date = Date()) {
        self.id = feed.id
        self.title = feed.title
        self.preview = FeedHTMLParser.plainText(feed.message)
        self.username = feed.username
        self.avatar = feed.userAvatar
        self.visitedAt = visitedAt
        self.feed = feed
    }
}

public struct LocalFavoriteFolder: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var createdAt: Date
    public var isCloudLinked: Bool

    public init(id: String = UUID().uuidString, title: String, createdAt: Date = Date(), isCloudLinked: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isCloudLinked = isCloudLinked
    }
}

public struct LocalFavoriteEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var folderID: String
    public var title: String
    public var preview: String
    public var username: String
    public var avatar: String
    public var savedAt: Date
    public var feed: FeedItem?
    public var isCloudSynced: Bool?

    public var resolvedIsCloudSynced: Bool {
        isCloudSynced ?? false
    }

    public init(
        feed: FeedItem,
        folderID: String = HistoryAndFavStore.defaultFolderID,
        savedAt: Date = Date(),
        isCloudSynced: Bool = false
    ) {
        self.id = feed.id
        self.folderID = folderID
        self.title = feed.title
        self.preview = FeedHTMLParser.plainText(feed.message)
        self.username = feed.username
        self.avatar = feed.userAvatar
        self.savedAt = savedAt
        self.feed = feed
        self.isCloudSynced = isCloudSynced
    }
}

public struct CachedCloudFavoriteEntry: Codable, Identifiable, Hashable, Sendable {
    public let collectionID: String
    public var collectionTitle: String
    public var feed: FeedItem

    public var id: String { "\(collectionID)-\(feed.id)" }

    public init(collectionID: String, collectionTitle: String, feed: FeedItem) {
        self.collectionID = collectionID
        self.collectionTitle = collectionTitle
        self.feed = feed
    }
}

private struct CloudFavoritesCachePayload: Codable {
    var collections: [CollectionItem]
    var entries: [CachedCloudFavoriteEntry]
}

@MainActor
@Observable
public final class HistoryAndFavStore {
    public static let defaultFolderID = "default"

    public private(set) var history: [LocalHistoryEntry] = []
    public private(set) var favorites: [LocalFavoriteEntry] = []
    public private(set) var folders: [LocalFavoriteFolder] = [
        LocalFavoriteFolder(id: "default", title: "默认收藏夹", createdAt: Date(timeIntervalSince1970: 0))
    ]
    public private(set) var cachedCloudCollections: [CollectionItem] = []
    public private(set) var cachedCloudEntries: [CachedCloudFavoriteEntry] = []

    private let historyURL: URL
    private let favoritesURL: URL
    private let foldersURL: URL
    private let cloudCacheURL: URL

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.historyURL = dir.appendingPathComponent("history_v1.json")
        self.favoritesURL = dir.appendingPathComponent("favorites_v1.json")
        self.foldersURL = dir.appendingPathComponent("favorite_folders_v1.json")
        self.cloudCacheURL = dir.appendingPathComponent("cloud_favorites_cache_v1.json")
        load()
    }

    public static func normalizedFolderTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func recordVisit(_ feed: FeedItem) {
        guard !feed.id.isEmpty else { return }
        history.removeAll { $0.id == feed.id }
        history.insert(LocalHistoryEntry(feed: feed), at: 0)
        if history.count > 400 {
            history = Array(history.prefix(400))
        }
        saveHistory()
    }

    public func backfillSnapshot(_ feed: FeedItem) {
        guard !feed.id.isEmpty else { return }
        var historyChanged = false
        for idx in history.indices where history[idx].id == feed.id && history[idx].feed == nil {
            history[idx].feed = feed
            historyChanged = true
        }
        if historyChanged { saveHistory() }

        var favChanged = false
        for idx in favorites.indices where favorites[idx].id == feed.id && favorites[idx].feed == nil {
            favorites[idx].feed = feed
            favChanged = true
        }
        if favChanged { saveFavorites() }
    }

    public func removeHistory(id: String) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    public func removeHistory(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        history.removeAll { ids.contains($0.id) }
        saveHistory()
    }

    public func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    public func isFavorited(id: String) -> Bool {
        favorites.contains { $0.id == id } || cachedCloudEntries.contains { $0.feed.id == id }
    }

    public func isLocallyFavorited(id: String) -> Bool {
        favorites.contains { $0.id == id && !$0.resolvedIsCloudSynced }
    }

    public func favoriteFolderID(for feedID: String) -> String? {
        favorites.first(where: { $0.id == feedID })?.folderID
    }

    @discardableResult
    public func createFolder(title: String) -> LocalFavoriteFolder {
        let trimmed = Self.normalizedFolderTitle(title)
        guard !trimmed.isEmpty else { return folders[0] }
        if let existingIdx = folders.firstIndex(where: { Self.normalizedFolderTitle($0.title) == trimmed }) {
            if folders[existingIdx].isCloudLinked {
                folders[existingIdx].isCloudLinked = false
                saveFolders()
            }
            return folders[existingIdx]
        }
        let folder = LocalFavoriteFolder(title: trimmed, isCloudLinked: false)
        folders.append(folder)
        saveFolders()
        return folder
    }

    @discardableResult
    public func ensureCloudMirrorFolder(id: String, title: String) -> LocalFavoriteFolder {
        let trimmed = Self.normalizedFolderTitle(title)
        let finalTitle = trimmed.isEmpty ? "云端收藏夹" : trimmed
        if let idx = folders.firstIndex(where: { $0.id == id }) {
            if folders[idx].title != finalTitle {
                folders[idx].title = finalTitle
                saveFolders()
            }
            return folders[idx]
        }
        if let sameNameIdx = folders.firstIndex(where: { Self.normalizedFolderTitle($0.title) == finalTitle }) {
            return folders[sameNameIdx]
        }
        let folder = LocalFavoriteFolder(id: id, title: finalTitle, isCloudLinked: true)
        folders.append(folder)
        saveFolders()
        return folder
    }

    public func updateCloudCache(collections: [CollectionItem], entries: [CachedCloudFavoriteEntry]) {
        self.cachedCloudCollections = collections
        self.cachedCloudEntries = entries
        saveCloudCache()
    }

    public func appendCloudCachedEntries(_ newEntries: [CachedCloudFavoriteEntry]) {
        let existingIDs = Set(cachedCloudEntries.map(\.id))
        let unique = newEntries.filter { !existingIDs.contains($0.id) }
        guard !unique.isEmpty else { return }
        cachedCloudEntries.append(contentsOf: unique)
        saveCloudCache()
    }

    public func removeCloudCachedEntries(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        cachedCloudEntries.removeAll { ids.contains($0.id) }
        saveCloudCache()
    }

    public func removeCloudCachedCollection(id: String) {
        cachedCloudCollections.removeAll { $0.id == id }
        cachedCloudEntries.removeAll { $0.collectionID == id }
        folders.removeAll { $0.id == id && $0.isCloudLinked }
        favorites.removeAll { $0.folderID == id && $0.resolvedIsCloudSynced }
        saveCloudCache()
        saveFolders()
        saveFavorites()
    }

    public func deleteFolder(id: String) {
        guard id != Self.defaultFolderID else { return }
        folders.removeAll { $0.id == id }
        favorites.removeAll { $0.folderID == id }
        saveFolders()
        saveFavorites()
    }

    public func deleteFolders(ids: Set<String>) {
        let valid = ids.subtracting([Self.defaultFolderID])
        guard !valid.isEmpty else { return }
        folders.removeAll { valid.contains($0.id) }
        favorites.removeAll { valid.contains($0.folderID) }
        saveFolders()
        saveFavorites()
    }

    public func saveFavorite(
        _ feed: FeedItem,
        folderID: String = HistoryAndFavStore.defaultFolderID,
        isCloudSynced: Bool = false
    ) {
        favorites.removeAll { $0.id == feed.id && $0.folderID == folderID }
        favorites.insert(
            LocalFavoriteEntry(feed: feed, folderID: folderID, isCloudSynced: isCloudSynced),
            at: 0
        )
        saveFavorites()
    }

    public func removeFavorite(id: String) {
        favorites.removeAll { $0.id == id }
        saveFavorites()
    }

    public func removeFavorites(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        favorites.removeAll { ids.contains($0.id) }
        saveFavorites()
    }

    public func toggleFavorite(_ feed: FeedItem, folderID: String = HistoryAndFavStore.defaultFolderID) -> Bool {
        if let idx = favorites.firstIndex(where: { $0.id == feed.id && !$0.resolvedIsCloudSynced }) {
            favorites.remove(at: idx)
            saveFavorites()
            return false
        } else {
            favorites.insert(LocalFavoriteEntry(feed: feed, folderID: folderID, isCloudSynced: false), at: 0)
            saveFavorites()
            return true
        }
    }

    public func favorites(inFolder folderID: String?) -> [LocalFavoriteEntry] {
        guard let folderID else { return favorites }
        return favorites.filter { $0.folderID == folderID }
    }

    public func count(inFolder folderID: String) -> Int {
        favorites.filter { $0.folderID == folderID }.count
    }

    private struct BackupPayload: Codable {
        var folders: [LocalFavoriteFolder]
        var favorites: [LocalFavoriteEntry]
    }

    public func exportBackupJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(BackupPayload(folders: folders, favorites: favorites))
    }

    @discardableResult
    public func importBackupJSON(_ data: Data) -> Int {
        if let payload = try? JSONDecoder().decode(BackupPayload.self, from: data) {
            for f in payload.folders where !folders.contains(where: { $0.id == f.id }) {
                folders.append(f)
            }
            var added = 0
            for item in payload.favorites where !favorites.contains(where: { $0.id == item.id }) {
                favorites.append(item)
                added += 1
            }
            saveFolders()
            saveFavorites()
            return added
        } else if let items = try? JSONDecoder().decode([LocalFavoriteEntry].self, from: data) {
            var added = 0
            for item in items where !favorites.contains(where: { $0.id == item.id }) {
                favorites.append(item)
                added += 1
            }
            saveFavorites()
            return added
        }
        return 0
    }

    private func load() {
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([LocalHistoryEntry].self, from: data) {
            self.history = decoded
        }
        if let data = try? Data(contentsOf: favoritesURL),
           let decoded = try? JSONDecoder().decode([LocalFavoriteEntry].self, from: data) {
            self.favorites = decoded
        }
        if let data = try? Data(contentsOf: foldersURL),
           let decoded = try? JSONDecoder().decode([LocalFavoriteFolder].self, from: data),
           !decoded.isEmpty {
            self.folders = decoded
            if !self.folders.contains(where: { $0.id == Self.defaultFolderID }) {
                self.folders.insert(
                    LocalFavoriteFolder(id: Self.defaultFolderID, title: "默认收藏夹", createdAt: Date(timeIntervalSince1970: 0)),
                    at: 0
                )
            }
        }
        if let data = try? Data(contentsOf: cloudCacheURL),
           let decoded = try? JSONDecoder().decode(CloudFavoritesCachePayload.self, from: data) {
            self.cachedCloudCollections = decoded.collections
            self.cachedCloudEntries = decoded.entries
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            try? data.write(to: favoritesURL, options: .atomic)
        }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            try? data.write(to: foldersURL, options: .atomic)
        }
    }

    private func saveCloudCache() {
        let payload = CloudFavoritesCachePayload(collections: cachedCloudCollections, entries: cachedCloudEntries)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cloudCacheURL, options: .atomic)
        }
    }
}
