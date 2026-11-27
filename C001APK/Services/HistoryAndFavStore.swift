import CoolapkKit
import Foundation
import Observation

public struct LocalCollectionFolder: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var isCloudLinked: Bool
    public var createdAt: Date

    public init(id: String, title: String, isCloudLinked: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isCloudLinked = isCloudLinked
        self.createdAt = createdAt
    }
}

public struct LocalHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var avatar: String
    public var title: String
    public var preview: String
    public var visitedAt: Date
    public var feed: FeedItem?

    public init(feed: FeedItem, visitedAt: Date = Date()) {
        self.id = feed.id
        self.username = feed.username
        self.avatar = feed.avatar
        self.title = feed.messageTitle.isEmpty ? feed.title : feed.messageTitle
        self.preview = FeedHTMLParser.plainText(feed.message)
        self.visitedAt = visitedAt
        var trimmed = feed
        trimmed.replyRows = []
        trimmed.topReplyRows = Array(feed.topReplyRows.prefix(2))
        self.feed = trimmed
    }
}

public struct LocalFavoriteEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var avatar: String
    public var title: String
    public var preview: String
    public var savedAt: Date
    public var feed: FeedItem?
    public var collectionID: String?
    public var collectionTitle: String?
    public var isCloudSynced: Bool?

    public var resolvedCollectionID: String { collectionID ?? HistoryAndFavStore.defaultFolderID }
    public var resolvedCollectionTitle: String { collectionTitle ?? HistoryAndFavStore.defaultFolderTitle }
    public var resolvedIsCloudSynced: Bool { isCloudSynced ?? false }

    public init(
        feed: FeedItem,
        savedAt: Date = Date(),
        collectionID: String = HistoryAndFavStore.defaultFolderID,
        collectionTitle: String = HistoryAndFavStore.defaultFolderTitle,
        isCloudSynced: Bool = false
    ) {
        self.id = feed.id
        self.username = feed.username
        self.avatar = feed.avatar
        self.title = feed.messageTitle.isEmpty ? feed.title : feed.messageTitle
        self.preview = FeedHTMLParser.plainText(feed.message)
        self.savedAt = savedAt
        self.collectionID = collectionID
        self.collectionTitle = collectionTitle
        self.isCloudSynced = isCloudSynced
        var trimmed = feed
        trimmed.replyRows = []
        trimmed.topReplyRows = Array(feed.topReplyRows.prefix(2))
        self.feed = trimmed
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
        var trimmed = feed
        trimmed.replyRows = []
        trimmed.topReplyRows = Array(feed.topReplyRows.prefix(2))
        self.feed = trimmed
    }
}

private struct CloudFavoritesCachePayload: Codable, Sendable {
    var collections: [CollectionItem]
    var entries: [CachedCloudFavoriteEntry]
}

public struct HistoryAndFavoritesBackup: Codable, Sendable {
    public var version: Int = 1
    public var exportedAt: Date = Date()
    public var folders: [LocalCollectionFolder]
    public var favorites: [LocalFavoriteEntry]
}

@MainActor
@Observable
public final class HistoryAndFavStore {
    nonisolated public static let defaultFolderID = "local-default"
    nonisolated public static let defaultFolderTitle = "默认收藏夹"

    nonisolated public static func normalizedFolderTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "默认本机收藏" || trimmed == "默认本机收藏夹" || trimmed == "默认收藏夹" || trimmed == "默认收藏" {
            return "默认收藏夹"
        }
        return trimmed
    }

    private let defaults = UserDefaults.standard
    private static let historyKey = "c001apk.localHistory.v1"
    private static let favoritesKey = "c001apk.localFavorites.v1"
    private static let foldersKey = "c001apk.localCollectionFolders.v1"
    private static let cloudCacheKey = "c001apk.cloudFavoritesCache.v2"

    public private(set) var history: [LocalHistoryEntry] = []
    public private(set) var favorites: [LocalFavoriteEntry] = []
    public private(set) var folders: [LocalCollectionFolder] = []
    public private(set) var cachedCloudCollections: [CollectionItem] = []
    public private(set) var cachedCloudEntries: [CachedCloudFavoriteEntry] = []

    public init() {
        if let hData = defaults.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([LocalHistoryEntry].self, from: hData) {
            history = decoded
        }
        if let fData = defaults.data(forKey: Self.favoritesKey),
           let decoded = try? JSONDecoder().decode([LocalFavoriteEntry].self, from: fData) {
            favorites = decoded
        }
        if let folderData = defaults.data(forKey: Self.foldersKey),
           let decoded = try? JSONDecoder().decode([LocalCollectionFolder].self, from: folderData) {
            folders = decoded
        }
        if let cloudData = defaults.data(forKey: Self.cloudCacheKey),
           let decoded = try? JSONDecoder().decode(CloudFavoritesCachePayload.self, from: cloudData) {
            cachedCloudCollections = decoded.collections
            cachedCloudEntries = decoded.entries
        }
        ensureDefaultFolderExists()
        deduplicateLocalFoldersIfNeeded()
    }

    private func ensureDefaultFolderExists() {
        if let idx = folders.firstIndex(where: { $0.id == Self.defaultFolderID }) {
            if folders[idx].title == "默认本机收藏" {
                folders[idx].title = Self.defaultFolderTitle
                persistFolders()
            }
        } else {
            folders.insert(
                LocalCollectionFolder(
                    id: Self.defaultFolderID,
                    title: Self.defaultFolderTitle,
                    isCloudLinked: false
                ),
                at: 0
            )
            persistFolders()
        }
    }

    public func deduplicateLocalFoldersIfNeeded() {
        var canonicalByNorm: [String: LocalCollectionFolder] = [:]
        var remapIDs: [String: String] = [:]
        var keptFolders: [LocalCollectionFolder] = []
        var didChangeFolders = false

        let sortedCandidates = folders.sorted { lhs, rhs in
            if lhs.id == Self.defaultFolderID { return true }
            if rhs.id == Self.defaultFolderID { return false }
            if !lhs.isCloudLinked && rhs.isCloudLinked { return true }
            if lhs.isCloudLinked && !rhs.isCloudLinked { return false }
            let lhsLocalPrefix = lhs.id.hasPrefix("local-")
            let rhsLocalPrefix = rhs.id.hasPrefix("local-")
            if lhsLocalPrefix && !rhsLocalPrefix { return true }
            if !lhsLocalPrefix && rhsLocalPrefix { return false }
            return lhs.createdAt < rhs.createdAt
        }

        for candidate in sortedCandidates {
            let norm = Self.normalizedFolderTitle(candidate.title)
            guard !norm.isEmpty else { continue }
            if canonicalByNorm[norm] == nil {
                var canonical = candidate
                if canonical.isCloudLinked {
                    canonical.isCloudLinked = false
                    didChangeFolders = true
                }
                if !canonical.id.hasPrefix("local-") && canonical.id != Self.defaultFolderID {
                    let oldID = canonical.id
                    let newID = "local-\(UUID().uuidString)"
                    canonical = LocalCollectionFolder(
                        id: newID,
                        title: canonical.title,
                        isCloudLinked: false,
                        createdAt: canonical.createdAt
                    )
                    remapIDs[oldID] = newID
                    didChangeFolders = true
                }
                canonicalByNorm[norm] = canonical
            } else if let canonical = canonicalByNorm[norm] {
                remapIDs[candidate.id] = canonical.id
                didChangeFolders = true
            }
        }

        var seenCanonicalIDs = Set<String>()
        for folder in folders {
            let norm = Self.normalizedFolderTitle(folder.title)
            if let canonical = canonicalByNorm[norm], seenCanonicalIDs.insert(canonical.id).inserted {
                keptFolders.append(canonical)
            } else {
                didChangeFolders = true
            }
        }

        if didChangeFolders {
            folders = keptFolders
            persistFolders()
        }

        var didChangeFavorites = false
        for i in favorites.indices {
            if !favorites[i].resolvedIsCloudSynced {
                let currentFolderID = favorites[i].resolvedCollectionID
                if let mappedID = remapIDs[currentFolderID] {
                    favorites[i].collectionID = mappedID
                    didChangeFavorites = true
                }
            }
        }
        if didChangeFavorites {
            var seenFavKeys = Set<String>()
            var uniqueFavs: [LocalFavoriteEntry] = []
            for fav in favorites {
                let key = "\(fav.id)|\(fav.resolvedCollectionID)|\(fav.resolvedIsCloudSynced)"
                if seenFavKeys.insert(key).inserted {
                    uniqueFavs.append(fav)
                }
            }
            favorites = uniqueFavs
            persistFavorites()
        }
    }

    @discardableResult
    public func createFolder(title: String, linkedCloudID: String? = nil) -> LocalCollectionFolder {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmed.isEmpty ? "新建收藏夹" : trimmed
        let norm = Self.normalizedFolderTitle(resolvedTitle)
        if linkedCloudID == nil,
           let sameNameIdx = folders.firstIndex(where: { Self.normalizedFolderTitle($0.title) == norm }) {
            if folders[sameNameIdx].isCloudLinked {
                folders[sameNameIdx].isCloudLinked = false
                persistFolders()
            }
            return folders[sameNameIdx]
        }
        let folderID = linkedCloudID ?? "local-\(UUID().uuidString)"
        if let existing = folders.first(where: { $0.id == folderID }) {
            return existing
        }
        let created = LocalCollectionFolder(
            id: folderID,
            title: resolvedTitle,
            isCloudLinked: linkedCloudID != nil
        )
        folders.append(created)
        persistFolders()
        return created
    }

    public func deleteFolder(id: String) {
        guard id != Self.defaultFolderID else { return }
        folders.removeAll { $0.id == id }
        favorites.removeAll { $0.resolvedCollectionID == id }
        persistFolders()
        persistFavorites()
    }

    public func updateCloudCache(collections: [CollectionItem], entries: [CachedCloudFavoriteEntry]) {
        cachedCloudCollections = collections
        cachedCloudEntries = entries
        persistCloudCache()
    }

    public func appendCloudCachedEntries(_ newEntries: [CachedCloudFavoriteEntry]) {
        let existingIDs = Set(cachedCloudEntries.map(\.id))
        let unique = newEntries.filter { !existingIDs.contains($0.id) }
        guard !unique.isEmpty else { return }
        cachedCloudEntries.append(contentsOf: unique)
        persistCloudCache()
    }

    public func replaceCloudCachedEntries(forCollectionID collectionID: String, entries: [CachedCloudFavoriteEntry]) {
        cachedCloudEntries.removeAll { $0.collectionID == collectionID }
        cachedCloudEntries.append(contentsOf: entries)
        persistCloudCache()
    }

    public func removeCloudCachedEntries(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        cachedCloudEntries.removeAll { ids.contains($0.id) }
        persistCloudCache()
    }

    public func removeCloudCachedCollection(id: String) {
        cachedCloudCollections.removeAll { $0.id == id }
        cachedCloudEntries.removeAll { $0.collectionID == id }
        folders.removeAll { $0.id == id && $0.isCloudLinked }
        favorites.removeAll { $0.resolvedCollectionID == id && $0.resolvedIsCloudSynced }
        persistCloudCache()
        persistFolders()
        persistFavorites()
    }

    public func recordVisit(_ feed: FeedItem, enabled: Bool) {
        if let idx = favorites.firstIndex(where: { $0.id == feed.id && $0.feed == nil }) {
            let existing = favorites[idx]
            favorites[idx] = LocalFavoriteEntry(
                feed: feed,
                savedAt: existing.savedAt,
                collectionID: existing.resolvedCollectionID,
                collectionTitle: existing.resolvedCollectionTitle,
                isCloudSynced: existing.resolvedIsCloudSynced
            )
            persistFavorites()
        }
        guard enabled, !feed.id.isEmpty else { return }
        history.removeAll { $0.id == feed.id }
        history.insert(LocalHistoryEntry(feed: feed), at: 0)
        if history.count > 200 { history = Array(history.prefix(200)) }
        persistHistory()
    }

    public func removeHistory(id: String) {
        history.removeAll { $0.id == id }
        persistHistory()
    }

    public func removeHistory(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        history.removeAll { ids.contains($0.id) }
        persistHistory()
    }

    public func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    public func isLocallyFavorited(id: String) -> Bool {
        favorites.contains { $0.id == id && !$0.resolvedIsCloudSynced }
    }

    public func isFavorited(feedID: String, inFolder folderID: String) -> Bool {
        isLocallyFavorited(feedID: feedID, inLocalFolderID: folderID)
    }

    public func isLocallyFavorited(feedID: String, inLocalFolderID folderID: String) -> Bool {
        let targetNorm: String? = folders.first(where: { $0.id == folderID }).map { Self.normalizedFolderTitle($0.title) }
        return favorites.contains { entry in
            guard entry.id == feedID && !entry.resolvedIsCloudSynced else { return false }
            if entry.resolvedCollectionID == folderID { return true }
            if let targetNorm,
               let entryFolder = folders.first(where: { $0.id == entry.resolvedCollectionID }),
               Self.normalizedFolderTitle(entryFolder.title) == targetNorm {
                return true
            }
            return false
        }
    }

    public func isCloudFavorited(feedID: String, inCloudCollection col: CollectionItem) -> Bool {
        if col.isBeCollected { return true }
        if cachedCloudEntries.contains(where: { $0.feed.id == feedID && $0.collectionID == col.id }) {
            return true
        }
        return favorites.contains {
            $0.id == feedID && $0.resolvedCollectionID == col.id && $0.resolvedIsCloudSynced
        }
    }

    public func favorites(inFolder folderID: String?) -> [LocalFavoriteEntry] {
        guard let folderID, !folderID.isEmpty else { return favorites }
        return favorites.filter { $0.resolvedCollectionID == folderID }
    }

    public func count(inFolder folderID: String) -> Int {
        let targetNorm: String? = folders.first(where: { $0.id == folderID }).map { Self.normalizedFolderTitle($0.title) }
        return favorites.filter { entry in
            guard !entry.resolvedIsCloudSynced else { return false }
            if entry.resolvedCollectionID == folderID { return true }
            if let targetNorm,
               let entryFolder = folders.first(where: { $0.id == entry.resolvedCollectionID }),
               Self.normalizedFolderTitle(entryFolder.title) == targetNorm {
                return true
            }
            return false
        }.count
    }

    public func toggleLocalFavorite(_ feed: FeedItem) {
        if isLocallyFavorited(id: feed.id) {
            favorites.removeAll { $0.id == feed.id && !$0.resolvedIsCloudSynced }
        } else {
            ensureDefaultFolderExists()
            favorites.insert(LocalFavoriteEntry(feed: feed, isCloudSynced: false), at: 0)
        }
        persistFavorites()
    }

    public func saveFavorite(
        _ feed: FeedItem,
        folderID: String,
        folderTitle: String,
        isCloudSynced: Bool
    ) {
        if isCloudSynced {
            appendCloudCachedEntries([CachedCloudFavoriteEntry(collectionID: folderID, collectionTitle: folderTitle, feed: feed)])
            return
        }
        ensureDefaultFolderExists()
        let resolvedLocalFolder: LocalCollectionFolder = {
            if let byID = folders.first(where: { $0.id == folderID && ($0.id == Self.defaultFolderID || $0.id.hasPrefix("local-")) && !$0.isCloudLinked }) {
                return byID
            }
            let trimmedTitle = folderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                return createFolder(title: trimmedTitle, linkedCloudID: nil)
            }
            return folders.first(where: { $0.id == Self.defaultFolderID })
                ?? createFolder(title: Self.defaultFolderTitle, linkedCloudID: nil)
        }()
        favorites.removeAll { $0.id == feed.id && !$0.resolvedIsCloudSynced }
        favorites.insert(
            LocalFavoriteEntry(
                feed: feed,
                collectionID: resolvedLocalFolder.id,
                collectionTitle: resolvedLocalFolder.title,
                isCloudSynced: false
            ),
            at: 0
        )
        persistFavorites()
    }

    public func removeFavorite(id: String) {
        favorites.removeAll { $0.id == id }
        persistFavorites()
    }

    public func removeFavorites(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        favorites.removeAll { ids.contains($0.id) }
        persistFavorites()
    }

    public func backfillSnapshot(_ feed: FeedItem) {
        guard !feed.id.isEmpty else { return }
        var changedHistory = false
        if let idx = history.firstIndex(where: { $0.id == feed.id && $0.feed == nil }) {
            let date = history[idx].visitedAt
            history[idx] = LocalHistoryEntry(feed: feed, visitedAt: date)
            changedHistory = true
        }
        if changedHistory { persistHistory() }

        var changedFav = false
        if let idx = favorites.firstIndex(where: { $0.id == feed.id && $0.feed == nil }) {
            let existing = favorites[idx]
            favorites[idx] = LocalFavoriteEntry(
                feed: feed,
                savedAt: existing.savedAt,
                collectionID: existing.resolvedCollectionID,
                collectionTitle: existing.resolvedCollectionTitle,
                isCloudSynced: existing.resolvedIsCloudSynced
            )
            changedFav = true
        }
        if changedFav { persistFavorites() }
    }

    public func exportBackupJSON() -> Data? {
        let payload = HistoryAndFavoritesBackup(folders: folders, favorites: favorites)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(payload)
    }

    @discardableResult
    public func importBackupJSON(_ data: Data) -> Int {
        guard let decoded = try? JSONDecoder().decode(HistoryAndFavoritesBackup.self, from: data) else {
            return 0
        }
        var importedCount = 0
        for folder in decoded.folders where !folders.contains(where: { $0.id == folder.id }) {
            folders.append(folder)
        }
        ensureDefaultFolderExists()
        for entry in decoded.favorites where !favorites.contains(where: { $0.id == entry.id }) {
            favorites.append(entry)
            importedCount += 1
        }
        persistFolders()
        persistFavorites()
        return importedCount
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    private func persistFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: Self.favoritesKey)
        }
    }

    private func persistFolders() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: Self.foldersKey)
        }
    }

    private func persistCloudCache() {
        let payload = CloudFavoritesCachePayload(collections: cachedCloudCollections, entries: cachedCloudEntries)
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.cloudCacheKey)
        }
    }
}
