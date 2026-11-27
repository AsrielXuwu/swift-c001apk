import Foundation

public struct NotificationItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var rawEntityID: String
    public var type: String
    public var title: String
    public var message: String
    public var avatar: String
    public var username: String
    public var uid: String
    public var url: String
    public var targetURL: String
    public var feedID: String
    public var replyID: String
    public var isFollowNotification: Bool
    public var initialFeed: FeedItem?
    public var dateline: Date?
    public var datelineText: String
    public var isRead: Bool
    public var extraTitle: String
    public var extraPic: String
    public var action: String

    public init(json: JSON) {
        let baseID = json.id.exists ? json.id.identifier : json.entityId.identifier
        rawEntityID = baseID
        let actor = Self.firstNonEmpty([
            json.likeUid.identifier,
            json.fuid.identifier,
            json.fUserInfo.uid.identifier,
            json.fromuid.identifier,
            json.fromUserInfo.uid.identifier
        ])
        let stamp = json.likeTime.exists ? json.likeTime.string : json.dateline.string
        id = actor.isEmpty ? baseID : "\(baseID)-\(actor)-\(stamp)"
        type = json.type.string.isEmpty ? json.entityType.string : json.type.string

        let kind = Self.kind(json: json, type: type)
        switch kind {
        case .like:
            avatar = coolapkNormalizedURL(Self.firstNonEmpty([
                json.likeAvatar.string, json.likeUserInfo.userAvatar.string,
                json.userAvatar.string, json.fromUserAvatar.string,
                json.userInfo.userAvatar.string
            ]))
            username = Self.firstNonEmpty([
                json.likeUsername.string, json.likeUserInfo.username.string,
                json.username.string, json.fromusername.string,
                json.userInfo.username.string
            ])
            uid = Self.firstNonEmpty([
                json.likeUid.identifier, json.likeUserInfo.uid.identifier,
                json.fromuid.identifier, json.uid.identifier
            ])
        case .follow:
            avatar = coolapkNormalizedURL(Self.firstNonEmpty([
                json.fUserAvatar.string, json.fUserInfo.userAvatar.string,
                json.fromUserAvatar.string, json.fromUserInfo.userAvatar.string,
                json.userAvatar.string, json.userInfo.userAvatar.string
            ]))
            username = Self.firstNonEmpty([
                json.fusername.string, json.fUserInfo.username.string,
                json.fromusername.string, json.fromUserInfo.username.string,
                json.username.string, json.userInfo.username.string
            ])
            uid = Self.firstNonEmpty([
                json.fuid.identifier, json.fUserInfo.uid.identifier,
                json.fromuid.identifier, json.fromUserInfo.uid.identifier,
                json.userInfo.uid.identifier, json.uid.identifier
            ])
        case .message:
            avatar = coolapkNormalizedURL(Self.firstNonEmpty([
                json.messageUserInfo.userAvatar.string, json.fromUserAvatar.string, json.userAvatar.string,
            ]))
            username = Self.firstNonEmpty([
                json.messageUserInfo.username.string, json.fromusername.string, json.username.string,
            ])
            uid = Self.firstNonEmpty([
                json.messageUserInfo.uid.identifier, json.fromuid.identifier, json.uid.identifier
            ])
        case .system, .comment:
            avatar = coolapkNormalizedURL(Self.firstNonEmpty([
                json.fromUserAvatar.string, json.fromUserInfo.userAvatar.string,
                json.userAvatar.string, json.userInfo.userAvatar.string,
            ]))
            username = Self.firstNonEmpty([
                json.fromusername.string, json.fromUserInfo.username.string,
                json.username.string, json.userInfo.username.string,
            ])
            uid = Self.firstNonEmpty([
                json.fromuid.identifier, json.fromUserInfo.uid.identifier,
                json.userInfo.uid.identifier, json.uid.identifier
            ])
        }

        title = json.title.string
        message = Self.firstNonEmpty([json.note.string, json.message.string, json.infoHtml.string])
        let rawURL = json.url.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawExtraURL = json.extra_url.string.trimmingCharacters(in: .whitespacesAndNewlines)
        url = rawURL

        if uid.isEmpty, let extractedUID = Self.extractUserID(from: rawURL) ?? Self.extractUserID(from: message) {
            uid = extractedUID
        }

        dateline = json.dateline.date ?? json.likeTime.date ?? json.lastupdate.date
        datelineText = json.dateline_text.string
        isRead = json.is_read.exists ? json.is_read.int > 0 : (json.isnew.exists ? json.isnew.int == 0 : false)
        extraTitle = Self.firstNonEmpty([
            json.extra_title.string,
            json.feedInfo.message_title.string,
            FeedHTMLParser.plainText(json.feedInfo.message.string),
            FeedHTMLParser.plainText(json.targetRow.message.string),
            json.targetRow.title.string,
            json.feedTypeName.string
        ])
        extraPic = coolapkNormalizedURL(json.extra_pic.string)
        action = Self.action(json: json, type: type, kind: kind, extraTitle: json.feedTypeName.string.isEmpty ? extraTitle : json.feedTypeName.string)

        let lowerType = type.lowercased()
        let lowerEntityType = json.entityType.string.lowercased()
        let lowerSlug = json.slug.string.lowercased()
        let isFollow = (kind == .follow)
            || lowerType.contains("follow")
            || lowerSlug.contains("follow")
            || rawURL.lowercased().contains("followlist")
            || rawURL.lowercased().contains("fanslist")
            || action == "关注了你"
        isFollowNotification = isFollow

        let isReplyEntity = lowerEntityType == "feed_reply"
            || lowerEntityType == "reply"
            || ["feed_reply", "reply", "commentme", "feed_comment", "atcommentme", "at_comment_me"].contains(lowerType)
            || lowerSlug.contains("reply")
            || lowerSlug.contains("comment")
            || json.rid.exists
            || json.rrid.exists

        // Resolve parent feed ID and reply ID accurately so tapping a comment/reply notification
        // opens the parent feed instead of calling /v6/feed/detail with a reply ID or /v6/page/dataList.
        let explicitParentFeedID = [
            json.fid.identifier,
            json.feed_id.identifier,
            json.feedId.identifier,
            json.feedInfo.id.identifier,
            json.parentInfo.fid.identifier,
            json.targetRow.entityType.string == "feed" ? json.targetRow.id.identifier : ""
        ]
        .first { !$0.isEmpty && $0 != "0" }

        let extraFeedID = Self.extractFeedID(from: rawExtraURL)
        let noteFeedID = Self.extractFeedID(from: message)
        let urlFeedID = Self.extractFeedID(from: rawURL)

        if isReplyEntity {
            replyID = [baseID, json.rid.identifier, Self.extractQueryID(from: rawURL, key: "rid"), Self.extractQueryID(from: rawURL, key: "id")]
                .compactMap { $0 }
                .first { !$0.isEmpty && $0 != "0" } ?? ""
            if let explicitParentFeedID {
                feedID = explicitParentFeedID
            } else if let extraFeedID, extraFeedID != replyID {
                feedID = extraFeedID
            } else if let noteFeedID, noteFeedID != replyID {
                feedID = noteFeedID
            } else if let urlFeedID {
                feedID = urlFeedID
            } else if !replyID.isEmpty {
                feedID = replyID
            } else {
                feedID = ""
            }
        } else if !isFollow {
            replyID = ""
            feedID = [
                explicitParentFeedID,
                extraFeedID,
                urlFeedID,
                noteFeedID,
                (lowerEntityType == "feed" || kind == .like) && !baseID.isEmpty && baseID != "0" ? baseID : nil
            ]
            .compactMap { $0 }
            .first { !$0.isEmpty && $0 != "0" } ?? ""
        } else {
            replyID = ""
            feedID = ""
        }

        if isFollow {
            targetURL = uid.isEmpty ? "" : "/u/\(uid)"
        } else if !feedID.isEmpty {
            targetURL = "/feed/\(feedID)"
        } else if !rawExtraURL.isEmpty, FeedLink.resolve(rawExtraURL) != nil {
            targetURL = rawExtraURL
        } else if !rawURL.isEmpty, !rawURL.lowercased().contains("/notification/") {
            targetURL = rawURL
        } else if let linkInMessage = Self.extractFirstHref(from: message), !linkInMessage.lowercased().contains("/notification/") {
            targetURL = linkInMessage
        } else if !uid.isEmpty {
            targetURL = "/u/\(uid)"
        } else {
            targetURL = ""
        }

        if json.feedInfo.isObject && (!json.feedInfo.id.identifier.isEmpty || !json.feedInfo.message.string.isEmpty) {
            initialFeed = FeedItem(json: json.feedInfo)
        } else if json.targetRow.isObject && json.targetRow.entityType.string == "feed" && !json.targetRow.id.identifier.isEmpty {
            initialFeed = FeedItem(json: json.targetRow)
        } else if lowerEntityType == "feed" && !json.message.string.isEmpty && !baseID.isEmpty {
            initialFeed = FeedItem(json: json)
        } else {
            initialFeed = nil
        }
    }

    private enum Kind { case like, follow, system, message, comment }

    private static func kind(json: JSON, type: String) -> Kind {
        let lower = type.lowercased()
        switch lower {
        case "notify_xms", "notification": return .system
        case "feedlike", "like", "feed_like": return .like
        case "contacts_follow", "follow", "user_follow", "contacts": return .follow
        case "message", "chat": return .message
        case "feed_reply", "reply", "commentme", "feed_comment",
             "atme", "at_me", "atcommentme", "at_comment_me": return .comment
        default: break
        }
        if json.fuid.exists || json.fUserInfo.exists || json.url.string.lowercased().contains("followlist") {
            return .follow
        }
        if json.likeAvatar.exists || json.likeUsername.exists || json.feedTypeName.exists { return .like }
        if json.messageUserInfo.exists || json.ukey.exists { return .message }
        if json.fromUserAvatar.exists || json.note.exists { return .system }
        return .comment
    }

    private static func action(json: JSON, type: String, kind: Kind, extraTitle: String) -> String {
        if kind == .follow { return "关注了你" }
        switch type.lowercased() {
        case "notify_xms", "notification": return "系统通知"
        case "feed_reply", "reply", "commentme", "feed_comment": return "评论了你"
        case "atme", "at_me": return "提到了你"
        case "atcommentme", "at_comment_me": return "在评论里提到了你"
        case "feedlike", "like", "feed_like":
            let kindName = json.feedTypeName.string.isEmpty ? "动态" : json.feedTypeName.string
            return "赞了你的\(kindName)"
        case "contacts_follow", "follow": return "关注了你"
        case "message", "chat": return "给你发了私信"
        default: break
        }
        if json.likeAvatar.exists || json.likeUsername.exists || json.feedTypeName.exists {
            let kindName = json.feedTypeName.string.isEmpty ? "动态" : json.feedTypeName.string
            return "赞了你的\(kindName)"
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

    private static func extractFeedID(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let patterns = [
            #"(?:fid|feed_id|feedId)=(\d+)"#,
            #"/(?:feed|question|picture|dyhArticle|answer)/(\d+)"#,
            #"/(?:feed/detail|feed/replyList|feed/replyDetail)\?[^"'\s<>]*?id=(\d+)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let val = String(text[range])
                if !val.isEmpty && val != "0" {
                    return val
                }
            }
        }
        return nil
    }

    private static func extractUserID(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let patterns = [
            #"(?:uid|fuid)=(\d+)"#,
            #"/(?:u|user)/(\d+)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let val = String(text[range])
                if !val.isEmpty && val != "0" {
                    return val
                }
            }
        }
        return nil
    }

    private static func extractQueryID(from urlString: String, key: String) -> String? {
        guard !urlString.isEmpty,
              let regex = try? NSRegularExpression(pattern: "(?:\\?|&)\\(key)=(\\d+)"),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)),
              let range = Range(match.range(at: 1), in: urlString) else {
            return nil
        }
        let val = String(urlString[range])
        return (val.isEmpty || val == "0") ? nil : val
    }

    private static func extractFirstHref(from html: String) -> String? {
        guard html.contains("href=") else { return nil }
        let tokens = FeedHTMLParser.tokenize(html)
        var nonUserLink: String?
        var anyLink: String?
        for token in tokens {
            if case let .text(_, _, _, _, link) = token, let link, !link.isEmpty {
                if anyLink == nil { anyLink = link }
                if !link.hasPrefix("/u/") && !link.hasPrefix("/user/") {
                    nonUserLink = link
                }
            }
        }
        return nonUserLink ?? anyLink
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
        let rawAvatar = json.messageUserInfo.userAvatar.string.isEmpty
            ? (json.userAvatar.string.isEmpty ? json.messageUserAvatar.string : json.userAvatar.string)
            : json.messageUserInfo.userAvatar.string
        avatar = coolapkNormalizedURL(rawAvatar)
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
        self.fromAvatar = coolapkNormalizedURL(fromAvatar)
        self.message = message
        self.messagePic = coolapkNormalizedURL(messagePic)
        self.messageCard = messageCard
        self.dateline = dateline
        self.isLongTimeFlag = isLongTimeFlag
        self.deliveryState = deliveryState
    }

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        fromUID = json.fromuid.identifier
        fromUsername = json.fromusername.string
        let rawAvatar = json.fromUserAvatar.string.isEmpty ? json.userAvatar.string : json.fromUserAvatar.string
        fromAvatar = coolapkNormalizedURL(rawAvatar)
        message = json.message.string
        messagePic = coolapkNormalizedURL(json.message_pic.string)
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

    public mutating func clearAll() {
        notification = 0
        message = 0
        atMe = 0
        atCommentMe = 0
        commentMe = 0
        feedLike = 0
        contactsFollow = 0
    }

    public mutating func clear(forEndpointType endpointType: String) {
        switch endpointType {
        case "":
            message = 0
        case "commentMeList", "commentMe":
            commentMe = 0
        case "atMeList", "atMe":
            atMe = 0
            atCommentMe = 0
        case "feedLikeList", "feedLike":
            feedLike = 0
        case "contactsFollowList", "contactsFollow":
            contactsFollow = 0
        case "list", "notification":
            notification = 0
        default:
            break
        }
    }
}
