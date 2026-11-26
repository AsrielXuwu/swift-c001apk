import Foundation
import Observation

public struct LocalFollowUser: Codable, Identifiable, Hashable, Sendable {
    public let uid: String
    public var username: String
    public var avatar: String

    public var id: String { uid }

    public init(uid: String, username: String, avatar: String = "") {
        self.uid = uid
        self.username = username
        self.avatar = avatar
    }
}

@MainActor
@Observable
public final class LocalFollowStore {
    private let defaults = UserDefaults.standard
    private static let usersKey = "c001apk.localFollowUsers"
    private static let secretEnabledKey = "c001apk.secretFollowEnabled"

    public var secretFollowEnabled: Bool {
        didSet { defaults.set(secretFollowEnabled, forKey: Self.secretEnabledKey) }
    }

    public private(set) var users: [LocalFollowUser] = []

    public init() {
        self.secretFollowEnabled = defaults.bool(forKey: Self.secretEnabledKey)
        if let data = defaults.data(forKey: Self.usersKey),
           let decoded = try? JSONDecoder().decode([LocalFollowUser].self, from: data) {
            self.users = decoded
        }
    }

    public func contains(uid: String) -> Bool {
        users.contains { $0.uid == uid }
    }

    public func follow(uid: String, username: String, avatar: String) {
        guard !uid.isEmpty, uid.allSatisfy(\.isNumber) else { return }
        users.removeAll { $0.uid == uid }
        users.insert(LocalFollowUser(uid: uid, username: username, avatar: avatar), at: 0)
        persist()
    }

    public func unfollow(uid: String) {
        users.removeAll { $0.uid == uid }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(users) {
            defaults.set(data, forKey: Self.usersKey)
        }
    }
}
