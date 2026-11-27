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

public enum RootTab: Hashable, Sendable {
    case home
    case follow
    case swipe
    case profile
    case search
}

public enum AppRoute: Hashable, Sendable {
    case feed(id: String, initial: FeedItem? = nil, transitionID: String? = nil)
    case user(uid: String, initialUsername: String? = nil, initialAvatar: String? = nil, transitionID: String? = nil)
    case topic(tag: String, transitionID: String? = nil)
    case product(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case app(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case collection(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case dyh(id: String, initialTitle: String? = nil, transitionID: String? = nil)
    case event(id: String, initial: EventItem? = nil, transitionID: String? = nil)
    case page(link: String, title: String)
    case coolpic(tag: String)
    case messages
    case chat(ukey: String, uid: String, username: String, avatar: String)
    case history
    case favorites
    case localFollowList
    case myRecentVisits
    case myLikes
    case myReplies
    case accounts
    case settings
    case contentFilterSettings
    case blacklist(isTopic: Bool)
    case deviceIdentity
    case protocolParams
    case about
    case web(url: URL)

    public var transitionID: String? {
        switch self {
        case let .feed(_, _, id),
             let .user(_, _, _, id),
             let .topic(_, id),
             let .product(_, _, id),
             let .app(_, _, id),
             let .collection(_, _, id),
             let .dyh(_, _, id),
             let .event(_, _, id):
            return id
        default:
            return nil
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
            let resolvedTitle = titleArg
                ?? FeedLink.inferredPageTitle(from: link)
                ?? "列表"
            return .page(link: link, title: resolvedTitle)
        case let .web(url): return .web(url: url)
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
