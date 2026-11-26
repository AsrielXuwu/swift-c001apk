import Foundation
import Observation

@MainActor
@Observable
public final class BlacklistStore {
    private let defaults = UserDefaults.standard
    private static let userKey = "c001apk.blacklist.users"
    private static let topicKey = "c001apk.blacklist.topics"

    public private(set) var blockedUsers: [String] = []
    public private(set) var blockedTopics: [String] = []

    public var blockedUserSet: Set<String> { Set(blockedUsers) }
    public var blockedTopicSet: Set<String> { Set(blockedTopics) }

    public init() {
        blockedUsers = defaults.stringArray(forKey: Self.userKey) ?? []
        blockedTopics = defaults.stringArray(forKey: Self.topicKey) ?? []
    }

    public func isUserBlocked(_ uid: String) -> Bool {
        blockedUserSet.contains(uid)
    }

    public func toggleUser(_ uid: String) {
        guard !uid.isEmpty else { return }
        if isUserBlocked(uid) {
            blockedUsers.removeAll { $0 == uid }
        } else {
            blockedUsers.insert(uid, at: 0)
        }
        defaults.set(blockedUsers, forKey: Self.userKey)
    }

    public func addTopic(_ topic: String) {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !blockedTopicSet.contains(trimmed) else { return }
        blockedTopics.insert(trimmed, at: 0)
        defaults.set(blockedTopics, forKey: Self.topicKey)
    }

    public func removeTopic(_ topic: String) {
        blockedTopics.removeAll { $0 == topic }
        defaults.set(blockedTopics, forKey: Self.topicKey)
    }
}
