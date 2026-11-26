import Foundation

public enum FilterLevel: String, Codable, CaseIterable, Sendable {
    case standard
    case strict

    public var label: String {
        switch self {
        case .standard: return "标准"
        case .strict: return "严格"
        }
    }

    var rank: Int {
        switch self {
        case .standard: return 0
        case .strict: return 1
        }
    }
}

public enum FilterScope: String, Codable, CaseIterable, Hashable, Sendable {
    case feed
    case comment
    case user
}

public enum FilterRuleKind: String, Codable, CaseIterable, Sendable {
    case author
    case topic
    case text
}

public struct FilterInput: Sendable {
    public let scope: FilterScope
    public let id: String?
    public let authorUID: String?
    public let text: String
    public let topicIDs: Set<String>
    public let topicNames: Set<String>

    public init(
        scope: FilterScope,
        id: String? = nil,
        authorUID: String? = nil,
        text: String = "",
        topicIDs: Set<String> = [],
        topicNames: Set<String> = []
    ) {
        self.scope = scope
        self.id = id
        self.authorUID = authorUID
        self.text = text
        self.topicIDs = topicIDs
        self.topicNames = topicNames
    }

    public var contentKey: String? {
        guard let id, !id.isEmpty else { return nil }
        return "\(scope.rawValue):\(id)"
    }
}

public struct FilterMatch: Equatable, Sendable {
    public let ruleID: String
    public let reason: String
    public let kind: FilterRuleKind

    public init(ruleID: String, reason: String, kind: FilterRuleKind) {
        self.ruleID = ruleID
        self.reason = reason
        self.kind = kind
    }
}

public struct FilterRule: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var reason: String
    public var kind: FilterRuleKind
    public var level: FilterLevel
    public var scopes: Set<FilterScope>
    public var values: [String]
    public var groups: [[String]]
    public var maxDistance: Int
    public var exceptions: [String]
    public var reviewedAt: Date?
    public var sources: [String]

    public init(
        id: String,
        reason: String,
        kind: FilterRuleKind,
        level: FilterLevel = .standard,
        scopes: Set<FilterScope> = [.feed, .comment, .user],
        values: [String] = [],
        groups: [[String]] = [],
        maxDistance: Int = 80,
        exceptions: [String] = [],
        reviewedAt: Date? = nil,
        sources: [String] = []
    ) {
        self.id = id
        self.reason = reason
        self.kind = kind
        self.level = level
        self.scopes = scopes
        self.values = values
        self.groups = groups
        self.maxDistance = min(240, max(1, maxDistance))
        self.exceptions = exceptions
        self.reviewedAt = reviewedAt
        self.sources = sources
    }
}

public struct FilterRuleSet: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var revision: Int
    public var publishedAt: Date
    public var rules: [FilterRule]

    public init(
        schemaVersion: Int = 1,
        revision: Int,
        publishedAt: Date,
        rules: [FilterRule]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.publishedAt = publishedAt
        self.rules = rules
    }
}
