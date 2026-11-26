import CoolapkKit
import Foundation
import Observation

@MainActor
@Observable
public final class ContentFilterService {
    public static let rulesURL = URL(string: "https://raw.githubusercontent.com/TG-Twilight/c001apk/filters/rules.json")!
    private static let maxDownloadBytes = 1024 * 1024

    private let defaults = UserDefaults.standard
    private static let enabledKey = "c001apk.filter.enabled"
    private static let levelKey = "c001apk.filter.level"
    private static let disabledRulesKey = "c001apk.filter.disabledRules"
    private static let disabledKindsKey = "c001apk.filter.disabledKinds"
    private static let allowedAuthorsKey = "c001apk.filter.allowedAuthors"
    private static let allowedContentKey = "c001apk.filter.allowedContent"
    private static let personalRulesKey = "c001apk.filter.personalRules"
    private static let subscriptionKey = "c001apk.filter.subscription"
    private static let lastCheckedKey = "c001apk.filter.lastChecked"

    public var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            if enabled { Task { await checkForUpdates() } }
        }
    }

    public var level: FilterLevel {
        didSet { defaults.set(level.rawValue, forKey: Self.levelKey) }
    }

    public private(set) var ruleSet: FilterRuleSet
    public private(set) var personalRules: [FilterRule] = []
    public private(set) var disabledRuleIDs: Set<String> = []
    public private(set) var disabledListKinds: Set<FilterRuleKind> = []
    public private(set) var allowedAuthorUIDs: Set<String> = []
    public private(set) var allowedContentKeys: Set<String> = []
    public private(set) var lastCheckedAt: Date?
    public private(set) var isUpdating = false
    public private(set) var updateMessage: String?

    private var subscriptionEngine: ContentFilterEngine
    private var personalEngine: ContentFilterEngine

    public init() {
        let isEnabled = defaults.bool(forKey: Self.enabledKey)
        let savedLevel = FilterLevel(rawValue: defaults.string(forKey: Self.levelKey) ?? "") ?? .standard
        self.enabled = isEnabled
        self.level = savedLevel

        self.disabledRuleIDs = Set(defaults.stringArray(forKey: Self.disabledRulesKey) ?? [])
        self.disabledListKinds = Set((defaults.stringArray(forKey: Self.disabledKindsKey) ?? []).compactMap(FilterRuleKind.init(rawValue:)))
        self.allowedAuthorUIDs = Set(defaults.stringArray(forKey: Self.allowedAuthorsKey) ?? [])
        self.allowedContentKeys = Set(defaults.stringArray(forKey: Self.allowedContentKey) ?? [])

        if let ts = defaults.object(forKey: Self.lastCheckedKey) as? TimeInterval {
            self.lastCheckedAt = Date(timeIntervalSince1970: ts)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loadedRuleSet = BuiltinFilterRules.defaultRuleSet
        if let subData = defaults.data(forKey: Self.subscriptionKey),
           let parsed = try? decoder.decode(FilterRuleSet.self, from: subData),
           parsed.revision >= loadedRuleSet.revision {
            loadedRuleSet = parsed
        }
        self.ruleSet = loadedRuleSet

        if let pData = defaults.data(forKey: Self.personalRulesKey),
           let parsedPersonal = try? decoder.decode([FilterRule].self, from: pData) {
            self.personalRules = parsedPersonal.filter { $0.id.hasPrefix("personal.") }
        }

        self.subscriptionEngine = ContentFilterEngine(ruleSet: Self.filteredRuleSet(loadedRuleSet, disabledKinds: self.disabledListKinds))
        self.personalEngine = ContentFilterEngine(ruleSet: FilterRuleSet(revision: 1, publishedAt: Date(), rules: self.personalRules))
    }

    public func isListEnabled(_ kind: FilterRuleKind) -> Bool {
        !disabledListKinds.contains(kind)
    }

    public func setListEnabled(_ kind: FilterRuleKind, _ isOn: Bool) {
        if isOn {
            disabledListKinds.remove(kind)
            let groupIDs = Set(ruleSet.rules.filter { $0.kind == kind }.map(\.id))
            disabledRuleIDs.subtract(groupIDs)
        } else {
            disabledListKinds.insert(kind)
        }
        defaults.set(disabledListKinds.map(\.rawValue), forKey: Self.disabledKindsKey)
        defaults.set(Array(disabledRuleIDs), forKey: Self.disabledRulesKey)
        rebuildEngines()
    }

    public func setRuleDisabled(_ id: String, _ disabled: Bool) {
        if disabled { disabledRuleIDs.insert(id) } else { disabledRuleIDs.remove(id) }
        defaults.set(Array(disabledRuleIDs), forKey: Self.disabledRulesKey)
    }

    public func allowAuthor(_ uid: String, allowed: Bool = true) {
        if allowed { allowedAuthorUIDs.insert(uid) } else { allowedAuthorUIDs.remove(uid) }
        defaults.set(Array(allowedAuthorUIDs), forKey: Self.allowedAuthorsKey)
    }

    public func allowContent(scope: FilterScope, id: String, allowed: Bool = true) {
        let key = "\(scope.rawValue):\(id)"
        if allowed { allowedContentKeys.insert(key) } else { allowedContentKeys.remove(key) }
        defaults.set(Array(allowedContentKeys), forKey: Self.allowedContentKey)
    }

    public func addPersonalRule(kind: FilterRuleKind, keyword: String, reason: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, personalRules.count < 200 else { return }
        let id = "personal.\(UUID().uuidString.prefix(8))"
        let rule: FilterRule
        switch kind {
        case .author:
            rule = FilterRule(id: id, reason: reason.isEmpty ? "个人屏蔽作者" : reason, kind: .author, values: [trimmed])
        case .topic:
            rule = FilterRule(id: id, reason: reason.isEmpty ? "个人屏蔽话题" : reason, kind: .topic, values: [trimmed])
        case .text:
            rule = FilterRule(id: id, reason: reason.isEmpty ? "个人屏蔽词" : reason, kind: .text, scopes: [.feed, .comment], groups: [[trimmed]])
        }
        personalRules.insert(rule, at: 0)
        persistPersonal()
        rebuildEngines()
    }

    public func removePersonalRule(id: String) {
        personalRules.removeAll { $0.id == id }
        persistPersonal()
        rebuildEngines()
    }

    public func match(feed: FeedItem) -> FilterMatch? {
        guard enabled else { return nil }
        let text = [feed.messageTitle, feed.title, feed.message, feed.sourceFeed?.message ?? ""].joined(separator: "\n")
        return evaluate(FilterInput(
            scope: .feed,
            id: feed.id,
            authorUID: feed.uid,
            text: text,
            topicIDs: Set(feed.topicIDs),
            topicNames: Set(feed.topicTags)
        ))
    }

    public func match(reply: ReplyItem) -> FilterMatch? {
        guard enabled else { return nil }
        return evaluate(FilterInput(
            scope: .comment,
            id: reply.id,
            authorUID: reply.uid,
            text: reply.message
        ))
    }

    public func match(user: UserBrief) -> FilterMatch? {
        guard enabled else { return nil }
        return evaluate(FilterInput(
            scope: .user,
            id: user.id,
            authorUID: user.id,
            text: "\(user.username)\n\(user.bio)"
        ))
    }

    public func evaluate(_ input: FilterInput) -> FilterMatch? {
        guard enabled else { return nil }
        return personalEngine.evaluate(
            input,
            level: level,
            disabledRuleIDs: disabledRuleIDs,
            allowedAuthorUIDs: allowedAuthorUIDs,
            allowedContentKeys: allowedContentKeys
        ) ?? subscriptionEngine.evaluate(
            input,
            level: level,
            disabledRuleIDs: disabledRuleIDs,
            allowedAuthorUIDs: allowedAuthorUIDs,
            allowedContentKeys: allowedContentKeys
        )
    }

    public func checkForUpdates() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        do {
            var request = URLRequest(url: Self.rulesURL)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("c001apk-ios-filter/1", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                updateMessage = "规则更新失败"
                return
            }
            guard data.count <= Self.maxDownloadBytes else {
                updateMessage = "规则文件超出大小限制"
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let parsed = try decoder.decode(FilterRuleSet.self, from: data)
            guard !parsed.rules.contains(where: { $0.id.hasPrefix("personal.") }) else {
                updateMessage = "订阅规则命名空间无效"
                return
            }
            lastCheckedAt = Date()
            defaults.set(lastCheckedAt?.timeIntervalSince1970, forKey: Self.lastCheckedKey)
            if parsed.revision >= ruleSet.revision {
                ruleSet = parsed
                defaults.set(data, forKey: Self.subscriptionKey)
                rebuildEngines()
                updateMessage = "规则已更新至 r\(parsed.revision)"
            } else {
                updateMessage = "当前已是最新规则 (r\(ruleSet.revision))"
            }
        } catch {
            updateMessage = "规则检查失败：\(error.localizedDescription)"
        }
    }

    private func rebuildEngines() {
        subscriptionEngine = ContentFilterEngine(ruleSet: Self.filteredRuleSet(ruleSet, disabledKinds: disabledListKinds))
        personalEngine = ContentFilterEngine(ruleSet: FilterRuleSet(revision: 1, publishedAt: Date(), rules: personalRules))
    }

    private static func filteredRuleSet(_ set: FilterRuleSet, disabledKinds: Set<FilterRuleKind>) -> FilterRuleSet {
        FilterRuleSet(
            schemaVersion: set.schemaVersion,
            revision: set.revision,
            publishedAt: set.publishedAt,
            rules: set.rules.filter { !disabledKinds.contains($0.kind) }
        )
    }

    private func persistPersonal() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(personalRules) {
            defaults.set(data, forKey: Self.personalRulesKey)
        }
    }
}
