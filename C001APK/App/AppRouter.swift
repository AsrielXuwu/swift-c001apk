import CoolapkKit
import Foundation
import SwiftUI

public enum RootTab: Hashable, Sendable {
    case home
    case follow
    case messages
    case profile
    case search
}

public enum AppRoute: Hashable, Sendable {
    case feed(id: String, initial: FeedItem? = nil)
    case user(uid: String)
    case topic(tag: String)
    case product(id: String)
    case app(id: String)
    case collection(id: String)
    case dyh(id: String)
    case event(id: String)
    case page(link: String, title: String)
    case coolpic(tag: String)
    case chat(ukey: String, uid: String, username: String, avatar: String)
    case history
    case favorites
    case localFollowList
    case accounts
    case settings
    case contentFilterSettings
    case blacklist(isTopic: Bool)
    case deviceIdentity
    case protocolParams
    case about
    case web(url: URL)

    public static func from(feedLink: FeedLink) -> AppRoute {
        switch feedLink {
        case let .topic(tag): return .topic(tag: tag)
        case let .user(uid): return .user(uid: uid)
        case let .feed(id): return .feed(id: id)
        case let .product(id): return .product(id: id)
        case let .app(id): return .app(id: id)
        case let .collection(id): return .collection(id: id)
        case let .dyh(id): return .dyh(id: id)
        case let .event(id): return .event(id: id)
        case let .question(id): return .feed(id: id)
        case let .vote(id): return .feed(id: id)
        case let .page(link): return .page(link: link, title: "精选")
        case let .web(url): return .web(url: url)
        }
    }
}

public struct MediaViewerPresentation: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let items: [FeedMedia]
    public let initialIndex: Int

    public init(items: [FeedMedia], initialIndex: Int = 0) {
        self.items = items
        self.initialIndex = max(0, min(initialIndex, max(0, items.count - 1)))
    }
}

public enum ComposeMode: Identifiable, Sendable {
    case newFeed
    case forward(FeedItem)
    case replyToFeed(feedID: String, authorName: String)
    case replyToComment(targetID: String, replyToName: String)

    public var id: String {
        switch self {
        case .newFeed: return "newFeed"
        case let .forward(feed): return "forward-\(feed.id)"
        case let .replyToFeed(id, _): return "replyFeed-\(id)"
        case let .replyToComment(id, _): return "replyComment-\(id)"
        }
    }
}
