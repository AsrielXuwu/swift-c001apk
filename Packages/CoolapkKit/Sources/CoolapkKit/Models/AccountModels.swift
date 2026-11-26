import Foundation

public struct SavedAccount: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let uid: String
    public var username: String
    public var avatar: String
    public var level: Int
    public var exp: Int
    public var nextExp: Int
    public var needsRelogin: Bool

    public var id: String { uid }

    public init(
        uid: String,
        username: String,
        avatar: String = "",
        level: Int = 0,
        exp: Int = 0,
        nextExp: Int = 1,
        needsRelogin: Bool = false
    ) {
        self.uid = uid
        self.username = username
        self.avatar = avatar
        self.level = level
        self.exp = exp
        self.nextExp = max(1, nextExp)
        self.needsRelogin = needsRelogin
    }

    public var displayName: String {
        username.removingPercentEncoding ?? username
    }
}
