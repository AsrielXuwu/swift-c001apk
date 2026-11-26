import Foundation

public struct NotificationItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var type: String
    public var title: String
    public var message: String
    public var avatar: String
    public var username: String
    public var uid: String
    public var url: String
    public var dateline: Date?
    public var datelineText: String
    public var isRead: Bool
    public var extraTitle: String
    public var extraPic: String
    public var action: String

    public init(json: JSON) {
        let baseID = json.id.exists ? json.id.identifier : json.entityId.identifier
        let actor = json.likeUid.exists ? json.likeUid.identifier : (json.fromuid.exists ? json.fromuid.identifier : "")
        let stamp = json.likeTime.exists ? json.likeTime.string : json.dateline.string
        id = actor.isEmpty ? baseID : "\(baseID)-\(actor)-\(stamp)"
        type = json.type.string

        let kind = Self.kind(json: json, type: type)
        switch kind {
        case .like:
            avatar = Self.firstNonEmpty([
                json.likeAvatar.string, json.likeUserInfo.userAvatar.string,
                json.userAvatar.string, json.fromUserAvatar.string,
            ])
            username = Self.firstNonEmpty([
                json.likeUsername.string, json.likeUserInfo.username.string,
                json.username.string, json.fromusername.string,
            ])
            uid = Self.firstNonEmpty([json.likeUid.identifier, json.likeUserInfo.uid.identifier, json.fromuid.identifier])
        case .message:
            avatar = Self.firstNonEmpty([
                json.messageUserInfo.userAvatar.string, json.fromUserAvatar.string, json.userAvatar.string,
            ])
            username = Self.firstNonEmpty([
                json.messageUserInfo.username.string, json.fromusername.string, json.username.string,
            ])
            uid = Self.firstNonEmpty([json.messageUserInfo.uid.identifier, json.fromuid.identifier, json.uid.identifier])
        case .system, .comment:
            avatar = Self.firstNonEmpty([
                json.fromUserAvatar.string, json.fromUserInfo.userAvatar.string,
                json.userAvatar.string, json.userInfo.userAvatar.string,
            ])
            username = Self.firstNonEmpty([
                json.fromusername.string, json.fromUserInfo.username.string,
                json.username.string, json.userInfo.username.string,
            ])
            uid = Self.firstNonEmpty([json.fromuid.identifier, json.fromUserInfo.uid.identifier, json.uid.identifier])
        }

        title = json.title.string
        message = Self.firstNonEmpty([json.note.string, json.message.string, json.infoHtml.string])
        url = json.url.string
        dateline = json.dateline.date ?? json.likeTime.date ?? json.lastupdate.date
        datelineText = json.dateline_text.string
        isRead = json.is_read.exists ? json.is_read.int > 0 : (json.isnew.exists ? json.isnew.int == 0 : false)
        extraTitle = Self.firstNonEmpty([json.extra_title.string, json.feedTypeName.string])
        extraPic = json.extra_pic.string
        action = Self.action(json: json, type: type, extraTitle: extraTitle)
    }

    private enum Kind { case like, system, message, comment }

    private static func kind(json: JSON, type: String) -> Kind {
        switch type {
        case "notify_xms", "notification": return .system
        case "feedlike", "like", "feed_like": return .like
        case "message", "chat": return .message
        case "feed_reply", "reply", "commentme", "feed_comment",
             "atme", "at_me", "atcommentme", "at_comment_me",
             "contacts_follow", "follow": return .comment
        default: break
        }
        if json.likeAvatar.exists || json.likeUsername.exists || json.feedTypeName.exists { return .like }
        if json.messageUserInfo.exists || json.ukey.exists { return .message }
        if json.fromUserAvatar.exists || json.note.exists { return .system }
        return .comment
    }

    private static func action(json: JSON, type: String, extraTitle: String) -> String {
        switch type {
        case "notify_xms", "notification": return "系统通知"
        case "feed_reply", "reply", "commentme", "feed_comment": return "评论了你"
        case "atme", "at_me": return "提到了你"
        case "atcommentme", "at_comment_me": return "在评论里提到了你"
        case "feedlike", "like", "feed_like": return extraTitle.isEmpty ? "赞了你" : "赞了你的\(extraTitle)"
        case "contacts_follow", "follow": return "关注了你"
        case "message", "chat": return "给你发了私信"
        default: break
        }
        if json.likeAvatar.exists || json.likeUsername.exists || json.feedTypeName.exists {
            return extraTitle.isEmpty ? "赞了你" : "赞了你的\(extraTitle)"
        }
        if json.messageUserInfo.exists || json.ukey.exists { return "给你发了私信" }
        if json.ruid.exists || json.rusername.exists { return "回复了你" }
        if json.note.exists || json.fromUserAvatar.exists { return "系统通知" }
        if json.parentInfo.exists || json.message.exists { return "评论了你" }
        return extraTitle.isEmpty ? type : extraTitle
    }

    private static func firstNonEmpty(_ values: [String]) -> String {
        values.first { !$0.isEmpty } ?? ""
    }
}

public struct MessageThread: Identifiable, Hashable, Sendable {
    public let id: String
    public var ukey: String
    public var uid: String
    public var username: String
    public var avatar: String
    public var message: String
    public var dateline: Date?
    public var unreadNum: Int

    public init(json: JSON) {
        let resolvedUID = json.messageUserInfo.uid.exists
            ? json.messageUserInfo.uid.identifier
            : (json.uid.exists ? json.uid.identifier : json.fromuid.identifier)
        id = json.id.exists ? json.id.identifier : resolvedUID
        ukey = json.ukey.string.isEmpty ? resolvedUID : json.ukey.string
        uid = resolvedUID
        username = json.messageUserInfo.username.string.isEmpty
            ? (json.username.string.isEmpty ? json.messageUsername.string : json.username.string)
            : json.messageUserInfo.username.string
        avatar = json.messageUserInfo.userAvatar.string.isEmpty
            ? (json.userAvatar.string.isEmpty ? json.messageUserAvatar.string : json.userAvatar.string)
            : json.messageUserInfo.userAvatar.string
        message = json.message.string
        dateline = json.dateline.date ?? json.lastupdate.date
        unreadNum = json.unread_num.int
    }
}

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public enum DeliveryState: Hashable, Sendable {
        case sending
        case sent
        case failed(String)
    }

    public let id: String
    public var fromUID: String
    public var fromUsername: String
    public var fromAvatar: String
    public var message: String
    public var messagePic: String
    public var messageCard: String
    public var dateline: Date?
    public var isLongTimeFlag: Bool
    public var deliveryState: DeliveryState

    public init(
        id: String,
        fromUID: String,
        fromUsername: String = "",
        fromAvatar: String = "",
        message: String,
        messagePic: String = "",
        messageCard: String = "",
        dateline: Date? = Date(),
        isLongTimeFlag: Bool = false,
        deliveryState: DeliveryState = .sent
    ) {
        self.id = id
        self.fromUID = fromUID
        self.fromUsername = fromUsername
        self.fromAvatar = fromAvatar
        self.message = message
        self.messagePic = messagePic
        self.messageCard = messageCard
        self.dateline = dateline
        self.isLongTimeFlag = isLongTimeFlag
        self.deliveryState = deliveryState
    }

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        fromUID = json.fromuid.identifier
        fromUsername = json.fromusername.string
        fromAvatar = json.fromUserAvatar.string.isEmpty ? json.userAvatar.string : json.fromUserAvatar.string
        message = json.message.string
        messagePic = json.message_pic.string
        messageCard = json.message_card.string
        dateline = json.dateline.date
        isLongTimeFlag = json.entityTemplate.string == "time" || json.entityType.string == "time"
        deliveryState = .sent
    }
}

public struct NotificationBadge: Equatable, Hashable, Sendable {
    public var notification = 0
    public var message = 0
    public var atMe = 0
    public var atCommentMe = 0
    public var commentMe = 0
    public var feedLike = 0
    public var contactsFollow = 0

    public var total: Int { notification + message + atMe + atCommentMe + commentMe + feedLike + contactsFollow }

    public init(json: JSON = .null) {
        notification = json.notification.int
        message = json.message.int
        atMe = json.atme.int
        atCommentMe = json.atcommentme.int
        commentMe = json.commentme.int
        feedLike = json.feedlike.int
        contactsFollow = json.contacts_follow.int
    }
}
