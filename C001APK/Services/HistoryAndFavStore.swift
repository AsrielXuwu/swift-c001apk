import CoolapkKit
import Foundation
import Observation

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

    public init(feed: FeedItem, savedAt: Date = Date()) {
        self.id = feed.id
        self.username = feed.username
        self.avatar = feed.avatar
        self.title = feed.messageTitle.isEmpty ? feed.title : feed.messageTitle
        self.preview = FeedHTMLParser.plainText(feed.message)
        self.savedAt = savedAt
        var trimmed = feed
        trimmed.replyRows = []
        trimmed.topReplyRows = Array(feed.topReplyRows.prefix(2))
        self.feed = trimmed
    }
}

@MainActor
@Observable
public final class HistoryAndFavStore {
    private let defaults = UserDefaults.standard
    private static let historyKey = "c001apk.localHistory.v1"
    private static let favoritesKey = "c001apk.localFavorites.v1"

    public private(set) var history: [LocalHistoryEntry] = []
    public private(set) var favorites: [LocalFavoriteEntry] = []

    public init() {
        if let hData = defaults.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([LocalHistoryEntry].self, from: hData) {
            history = decoded
        }
        if let fData = defaults.data(forKey: Self.favoritesKey),
           let decoded = try? JSONDecoder().decode([LocalFavoriteEntry].self, from: fData) {
            favorites = decoded
        }
    }

    public func recordVisit(_ feed: FeedItem, enabled: Bool) {
        let idx = favorites.firstIndex { $0.id == feed.id }
        if let idx, favorites[idx].feed == nil {
            let existingDate = favorites[idx].savedAt
            favorites[idx] = LocalFavoriteEntry(feed: feed, savedAt: existingDate)
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

    public func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    public func isLocallyFavorited(id: String) -> Bool {
        favorites.contains { $0.id == id }
    }

    public func toggleLocalFavorite(_ feed: FeedItem) {
        if isLocallyFavorited(id: feed.id) {
            favorites.removeAll { $0.id == feed.id }
        } else {
            favorites.insert(LocalFavoriteEntry(feed: feed), at: 0)
        }
        persistFavorites()
    }

    public func removeFavorite(id: String) {
        favorites.removeAll { $0.id == id }
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
            let date = favorites[idx].savedAt
            favorites[idx] = LocalFavoriteEntry(feed: feed, savedAt: date)
            changedFav = true
        }
        if changedFav { persistFavorites() }
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
}
