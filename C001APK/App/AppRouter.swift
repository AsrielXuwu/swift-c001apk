import CoolapkKit
import Foundation
import SwiftUI

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct SuppressMediaTapKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public typealias MediaOpenAction = @MainActor @Sendable ([FeedMedia], Int, String?) -> Void

private struct MediaOpenActionKey: EnvironmentKey {
    static let defaultValue: MediaOpenAction? = nil
}

private struct OledPureBlackKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }

    var suppressMediaTap: Bool {
        get { self[SuppressMediaTapKey.self] }
        set { self[SuppressMediaTapKey.self] = newValue }
    }

    var mediaOpenAction: MediaOpenAction? {
        get { self[MediaOpenActionKey.self] }
        set { self[MediaOpenActionKey.self] = newValue }
    }

    var oledPureBlack: Bool {
        get { self[OledPureBlackKey.self] }
        set { self[OledPureBlackKey.self] = newValue }
    }
}

public struct C001PageBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.oledPureBlack) private var oledPureBlack

    public func body(content: Content) -> some View {
        let bg: Color = (colorScheme == .dark && oledPureBlack)
            ? .black
            : Color(.systemGroupedBackground)
        content.background(bg.ignoresSafeArea())
    }
}

public struct C001CardStyleModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.05),
                        lineWidth: 0.6
                    )
            }
    }
}

public struct C001NestedSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
            .background(
                Color(.tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04),
                        lineWidth: 0.5
                    )
            }
    }
}

public extension View {
    @ViewBuilder
    func applyZoomSource(id: String?, in namespace: Namespace.ID?, cornerRadius: CGFloat? = nil) -> some View {
        if let id, let namespace {
            if let cornerRadius {
                self.matchedTransitionSource(id: id, in: namespace) { configuration in
                    configuration
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            } else {
                self.matchedTransitionSource(id: id, in: namespace)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func applyZoomTransition(sourceID: String?, in namespace: Namespace.ID?) -> some View {
        if let sourceID, let namespace {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    func c001CardStyle(cornerRadius: CGFloat = 16) -> some View {
        modifier(C001CardStyleModifier(cornerRadius: cornerRadius))
    }

    func c001NestedSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(C001NestedSurfaceModifier(cornerRadius: cornerRadius))
    }

    func c001PageBackground() -> some View {
        modifier(C001PageBackgroundModifier())
    }

    func c001NativeTopBar() -> some View {
        self.scrollEdgeEffectStyle(.soft, for: .top)
    }
}

public enum RootTab: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case home = "home"
    case partition = "partition"
    case follow = "follow"
    case swipe = "swipe"
    case profile = "profile"
    case search = "search"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "首页"
        case .partition: return "分区"
        case .follow: return "关注"
        case .swipe: return "刷动态"
        case .profile: return "我的"
        case .search: return "搜索"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "house"
        case .partition: return "square.grid.2x2"
        case .follow: return "person.2"
        case .swipe: return "rectangle.stack"
        case .profile: return "person.crop.circle"
        case .search: return "magnifyingglass"
        }
    }
}

public struct RootTabConfiguration: Codable, Equatable, Sendable {
    public static let defaultOrder: [RootTab] = [
        .home,
        .partition,
        .follow,
        .swipe,
        .profile,
        .search
    ]

    public var order: [RootTab]
    public var hidden: Set<RootTab>

    public init(order: [RootTab] = RootTabConfiguration.defaultOrder, hidden: Set<RootTab> = []) {
        var resolved: [RootTab] = []
        for tab in order where Self.defaultOrder.contains(tab) && !resolved.contains(tab) {
            resolved.append(tab)
        }
        for tab in Self.defaultOrder where !resolved.contains(tab) {
            resolved.append(tab)
        }
        self.order = resolved
        // Keep .home and .profile always visible so user can always browse and access settings.
        self.hidden = hidden.subtracting([.home, .profile])
    }

    public var visibleTabs: [RootTab] {
        order.filter { !hidden.contains($0) }
    }
}

public enum AppRoute: Hashable, Sendable {
    case feed(id: String, initial: FeedItem? = nil, transitionID: String? = nil)
    case user(uid: String, initialUsername: String? = nil, initialAvatar: String? = nil, transitionID: String? = nil, initialTab: String? = nil)
    case topic(tag: String, transitionID: String? = nil)
    case product(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case app(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case collection(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case dyh(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case event(id: String, initial: EventItem? = nil, transitionID: String? = nil)
    case page(link: String, title: String, transitionID: String? = nil)
    case partitionHub(transitionID: String? = nil)
    case productCategoryBrowser(transitionID: String? = nil)
    case coolpic(tag: String, transitionID: String? = nil)
    case messages
    case chat(ukey: String, uid: String, username: String, avatar: String, transitionID: String? = nil)
    case history(transitionID: String? = nil)
    case favorites(transitionID: String? = nil)
    case localFollowList(transitionID: String? = nil)
    case myRecentVisits(transitionID: String? = nil)
    case myLikes(transitionID: String? = nil)
    case myReplies(transitionID: String? = nil)
    case accounts(transitionID: String? = nil)
    case settings(transitionID: String? = nil)
    case contentFilterSettings(transitionID: String? = nil)
    case blacklist(isTopic: Bool, transitionID: String? = nil)
    case deviceIdentity(transitionID: String? = nil)
    case protocolParams(transitionID: String? = nil)
    case about(transitionID: String? = nil)
    case web(url: URL, transitionID: String? = nil)

    public var transitionID: String? {
        switch self {
        case let .feed(_, _, id),
             let .user(_, _, _, id, _),
             let .topic(_, id),
             let .product(_, _, id),
             let .app(_, _, id),
             let .collection(_, _, id),
             let .dyh(_, _, id),
             let .event(_, _, id),
             let .page(_, _, id),
             let .partitionHub(id),
             let .productCategoryBrowser(id),
             let .coolpic(_, id),
             let .chat(_, _, _, _, id),
             let .history(id),
             let .favorites(id),
             let .localFollowList(id),
             let .myRecentVisits(id),
             let .myLikes(id),
             let .myReplies(id),
             let .accounts(id),
             let .settings(id),
             let .contentFilterSettings(id),
             let .blacklist(_, id),
             let .deviceIdentity(id),
             let .protocolParams(id),
             let .about(id),
             let .web(_, id):
            return id
        case .messages:
            return nil
        }
    }

    public func withTransitionID(_ id: String?) -> AppRoute {
        switch self {
        case let .feed(fid, initial, _): return .feed(id: fid, initial: initial, transitionID: id)
        case let .user(uid, name, avatar, _, tab): return .user(uid: uid, initialUsername: name, initialAvatar: avatar, transitionID: id, initialTab: tab)
        case let .topic(tag, _): return .topic(tag: tag, transitionID: id)
        case let .product(pid, title, _): return .product(id: pid, initialTitle: title, transitionID: id)
        case let .app(aid, title, _): return .app(id: aid, initialTitle: title, transitionID: id)
        case let .collection(cid, title, _): return .collection(id: cid, initialTitle: title, transitionID: id)
        case let .dyh(did, title, _): return .dyh(id: did, initialTitle: title, transitionID: id)
        case let .event(eid, initial, _): return .event(id: eid, initial: initial, transitionID: id)
        case let .page(link, title, _): return .page(link: link, title: title, transitionID: id)
        case .partitionHub: return .partitionHub(transitionID: id)
        case .productCategoryBrowser: return .productCategoryBrowser(transitionID: id)
        case let .coolpic(tag, _): return .coolpic(tag: tag, transitionID: id)
        case .messages: return .messages
        case let .chat(ukey, uid, username, avatar, _): return .chat(ukey: ukey, uid: uid, username: username, avatar: avatar, transitionID: id)
        case .history: return .history(transitionID: id)
        case .favorites: return .favorites(transitionID: id)
        case .localFollowList: return .localFollowList(transitionID: id)
        case .myRecentVisits: return .myRecentVisits(transitionID: id)
        case .myLikes: return .myLikes(transitionID: id)
        case .myReplies: return .myReplies(transitionID: id)
        case .accounts: return .accounts(transitionID: id)
        case .settings: return .settings(transitionID: id)
        case .contentFilterSettings: return .contentFilterSettings(transitionID: id)
        case let .blacklist(isTopic, _): return .blacklist(isTopic: isTopic, transitionID: id)
        case .deviceIdentity: return .deviceIdentity(transitionID: id)
        case .protocolParams: return .protocolParams(transitionID: id)
        case .about: return .about(transitionID: id)
        case let .web(url, _): return .web(url: url, transitionID: id)
        }
    }

    public static func from(feedLink: FeedLink, preferredTitle: String? = nil, transitionID: String? = nil) -> AppRoute {
        let cleanTitle = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleArg = (cleanTitle?.isEmpty == false) ? cleanTitle : nil
        switch feedLink {
        case let .topic(tag): return .topic(tag: tag, transitionID: transitionID)
        case let .user(uid): return .user(uid: uid, transitionID: transitionID)
        case let .feed(id): return .feed(id: id, transitionID: transitionID)
        case let .product(id): return .product(id: id, initialTitle: titleArg, transitionID: transitionID)
        case let .app(id): return .app(id: id, initialTitle: titleArg, transitionID: transitionID)
        case let .collection(id): return .collection(id: id, initialTitle: titleArg, transitionID: transitionID)
        case let .dyh(id): return .dyh(id: id, initialTitle: titleArg, transitionID: transitionID)
        case let .event(id): return .event(id: id, transitionID: transitionID)
        case let .question(id): return .feed(id: id, transitionID: transitionID)
        case let .vote(id): return .feed(id: id, transitionID: transitionID)
        case let .page(link):
            if link.lowercased().contains("/product/categorylist") {
                return .productCategoryBrowser(transitionID: transitionID)
            }
            let resolvedTitle = titleArg
                ?? FeedLink.inferredPageTitle(from: link)
                ?? "列表"
            return .page(link: link, title: resolvedTitle, transitionID: transitionID)
        case let .web(url): return .web(url: url, transitionID: transitionID)
        }
    }
}

public struct MediaViewerPresentation: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let items: [FeedMedia]
    public let initialIndex: Int
    public let sourcePrefix: String?

    public init(items: [FeedMedia], initialIndex: Int = 0, sourcePrefix: String? = nil) {
        self.items = items
        self.initialIndex = max(0, min(initialIndex, max(0, items.count - 1)))
        self.sourcePrefix = sourcePrefix
    }

    public func sourceID(at index: Int) -> String? {
        sourcePrefix.map { "\($0)-\(index)" }
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
