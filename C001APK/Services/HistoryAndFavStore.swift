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

    public init(feed: FeedItem, visitedAt: Date = Date()) {
        self.id = feed.id
        self.username = feed.username
        self.avatar = feed.avatar
        self.title = feed.messageTitle.isEmpty ? feed.title : feed.messageTitle
        self.preview = FeedHTMLParser.plainText(feed.message)
        self.visitedAt = visitedAt
    }
}

public struct LocalFavoriteEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var avatar: String
    public var title: String
    public var preview: String
    public var savedAt: Date

    public init(feed: FeedItem, savedAt: Date = Date()) {
        self.id = feed.id
        self.username = feed.username
        self.avatar = feed.avatar
        self.title = feed.messageTitle.isEmpty ? feed.title : feed.messageTitle
        self.preview = FeedHTMLParser.plainText(feed.message)
        self.savedAt = savedAt
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
