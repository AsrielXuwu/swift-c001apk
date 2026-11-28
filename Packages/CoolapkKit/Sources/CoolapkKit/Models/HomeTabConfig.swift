import Foundation

public enum HomeTabType: String, CaseIterable, Codable, Identifiable, Sendable {
    case follow
    case app
    case feed
    case hot
    case topic
    case product
    case dyh
    case coolpic
    case headline
    case question
    case goods
    case secondHand
    case review
    case game
    case none

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .follow: return "关注"
        case .app: return "应用"
        case .feed: return "动态"
        case .hot: return "热门"
        case .topic: return "话题"
        case .product: return "数码"
        case .dyh: return "看看号"
        case .coolpic: return "酷图"
        case .headline: return "头条"
        case .question: return "问答"
        case .goods: return "好物"
        case .secondHand: return "二手"
        case .review: return "评测"
        case .game: return "游戏"
        case .none: return "其他"
        }
    }
}

public struct HomeTabConfiguration: Codable, Equatable, Sendable {
    public static let defaultOrder: [HomeTabType] = [
        .feed,
        .hot,
        .headline,
        .topic,
        .product,
        .dyh,
        .secondHand,
        .review,
        .coolpic,
        .question,
        .goods,
        .app,
        .game
    ]

    public var order: [HomeTabType]
    public var hidden: Set<HomeTabType>

    public init(order: [HomeTabType] = HomeTabConfiguration.defaultOrder, hidden: Set<HomeTabType> = []) {
        var resolved: [HomeTabType] = []
        for tab in order where Self.defaultOrder.contains(tab) && !resolved.contains(tab) {
            resolved.append(tab)
        }
        for tab in Self.defaultOrder where !resolved.contains(tab) {
            resolved.append(tab)
        }
        self.order = resolved
        // Keep `.feed` always visible so Home never ends up empty.
        self.hidden = hidden.subtracting([.feed])
    }

    public var visibleTabs: [HomeTabType] {
        order.filter { !hidden.contains($0) }
    }
}
