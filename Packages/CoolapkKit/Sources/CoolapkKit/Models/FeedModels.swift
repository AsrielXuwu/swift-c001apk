import Foundation

public func coolapkNormalizedURL(_ url: String) -> String {
    guard !url.isEmpty else { return url }
    if url.hasPrefix("http://") { return "https://" + url.dropFirst("http://".count) }
    if url.hasPrefix("//") { return "https:" + url }
    return url
}

public enum MediaContentType: String, Sendable, Codable {
    case feed
    case reply
    case article
}

public struct FeedMedia: Hashable, Identifiable, Sendable, Codable {
    public var id: String { "\(sourceUrl)|\(videoUrl ?? "")" }
    public let sourceUrl: String
    public let previewUrl: String?
    public let videoUrl: String?
    public let isLivePhoto: Bool
    public let isHdr: Bool
    public let contentId: String?
    public let contentType: MediaContentType

    public init(
        sourceUrl: String,
        previewUrl: String? = nil,
        videoUrl: String? = nil,
        isLivePhoto: Bool = false,
        isHdr: Bool = false,
        contentId: String? = nil,
        contentType: MediaContentType = .feed
    ) {
        self.sourceUrl = coolapkNormalizedURL(sourceUrl)
        self.previewUrl = previewUrl.map(coolapkNormalizedURL)
        self.videoUrl = videoUrl.map(coolapkNormalizedURL)
        self.isLivePhoto = isLivePhoto || (videoUrl?.isEmpty == false)
        self.isHdr = isHdr
        self.contentId = contentId
        self.contentType = contentType
    }

    public var displayUrl: String { sourceUrl }
    public var thumbnailUrl: String { previewUrl?.isEmpty == false ? previewUrl! : sourceUrl }
    public var isGif: Bool { sourceUrl.lowercased().hasSuffix(".gif") }

    public static func from(json: JSON, contentId: String?, contentType: MediaContentType) -> [FeedMedia] {
        var result: [FeedMedia] = []
        let metadataList = json.imageUriList.exists ? json.imageUriList : json.image_uri_list
        if !metadataList.isNull {
            let parsedMeta = metadataList.isObject || !metadataList.array.isEmpty ? metadataList : metadataList.parsed
            for entry in parsedMeta.array {
                let url = [entry.url.string, entry.uri.string, entry.pic.string, entry.imageUrl.string, entry.image_url.string, entry.sourceUrl.string]
                    .first { !$0.isEmpty } ?? entry.string
                guard !url.isEmpty else { continue }
                let preview = [entry.previewUrl.string, entry.preview_url.string, entry.thumbnailUrl.string, entry.s_url.string].first { !$0.isEmpty }
                let video = [entry.videoUrl.string, entry.video_url.string, entry.livePhotoUrl.string, entry.live_photo_url.string].first { !$0.isEmpty }
                let live = entry.isLivePhoto.bool || entry.is_live_photo.bool || entry.is_live.bool || (video != nil)
                let hdr = entry.isHdr.bool || entry.is_hdr.bool || entry.hdr.bool
                result.append(FeedMedia(
                    sourceUrl: url,
                    previewUrl: preview,
                    videoUrl: video,
                    isLivePhoto: live,
                    isHdr: hdr,
                    contentId: contentId,
                    contentType: contentType
                ))
            }
        }
        if !result.isEmpty { return result }

        let pictures = json.picArr.array.map(\.string).filter { !$0.isEmpty }
        if !pictures.isEmpty {
            return pictures.map { FeedMedia(sourceUrl: $0, contentId: contentId, contentType: contentType) }
        }
        let single = json.pic.string.isEmpty ? json.media_pic.string : json.pic.string
        if !single.isEmpty {
            return [FeedMedia(sourceUrl: single, contentId: contentId, contentType: contentType)]
        }
        return []
    }
}

public struct FeedArticlePart: Hashable, Identifiable, Sendable, Codable {
    public let id: String
    public var type: String
    public var title: String
    public var message: String
    public var url: String
    public var description: String
    public var subTitle: String
    public var logo: String

    public init(
        id: String,
        type: String,
        title: String = "",
        message: String = "",
        url: String = "",
        description: String = "",
        subTitle: String = "",
        logo: String = ""
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.url = url
        self.description = description
        self.subTitle = subTitle
        self.logo = logo
    }

    public init(json: JSON, index: Int) {
        self.id = "part-\(index)-\(json.type.string)"
        self.type = json.type.string
        self.title = json.title.string
        self.message = json.message.string
        self.url = coolapkNormalizedURL(json.url.string)
        self.description = json.description.string
        self.subTitle = json.subTitle.string
        self.logo = coolapkNormalizedURL(json.logo.string)
    }
}

public struct VoteOption: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var title: String
    public var count: Int
    public var isSelected: Bool

    public init(json: JSON) {
        self.id = json.id.identifier
        self.title = json.title.string
        self.count = json.total_select_num.int > 0 ? json.total_select_num.int : json.select_num.int
        self.isSelected = json.is_select.bool
    }
}

public struct VoteInfo: Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var totalVotes: Int
    public var isMultiSelect: Bool
    public var endTimeText: String
    public var options: [VoteOption]

    public init?(json: JSON) {
        guard json.exists, !json.isNull else { return nil }
        let opts = json.options.array.map { VoteOption(json: $0) }
        guard !opts.isEmpty else { return nil }
        self.id = json.id.identifier
        self.title = json.message_title.string.isEmpty ? json.title.string : json.message_title.string
        self.totalVotes = json.total_vote_num.int > 0 ? json.total_vote_num.int : opts.reduce(0) { $0 + $1.count }
        self.isMultiSelect = json.max_select_num.int > 1
        self.endTimeText = json.end_time_text.string
        self.options = opts
    }
}

public struct ForwardedContent: Hashable, Sendable, Codable {
    public var id: String
    public var uid: String
    public var username: String
    public var avatar: String
    public var message: String
    public var pics: [String]
    public var mediaItems: [FeedMedia]
    public var datelineText: String
    public var feedType: String

    public init(json: JSON) {
        let resolvedID = json.id.exists ? json.id.identifier : json.entityId.identifier
        id = resolvedID
        uid = json.uid.identifier
        username = json.username.string
        avatar = coolapkNormalizedURL(json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string)
        message = json.message.string
        mediaItems = FeedMedia.from(json: json, contentId: resolvedID, contentType: .feed)
        pics = mediaItems.map(\.sourceUrl)
        datelineText = json.dateline_text.string
        feedType = json.feedType.string
    }
}

public struct ReplyItem: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var uid: String
    public var username: String
    public var avatar: String
    public var message: String
    public var replyToName: String
    public var replyToID: String
    public var rootID: String
    public var dateline: Date?
    public var datelineText: String
    public var likeNum: Int
    public var replyNum: Int
    public var isLiked: Bool
    public var isAuthor: Bool
    public var isTop: Bool
    public var pics: [String]
    public var mediaItems: [FeedMedia]
    public var nested: [ReplyItem]
    public var ipLocation: String

    public static func == (lhs: ReplyItem, rhs: ReplyItem) -> Bool {
        lhs.id == rhs.id && lhs.isLiked == rhs.isLiked && lhs.likeNum == rhs.likeNum && lhs.isTop == rhs.isTop && lhs.nested == rhs.nested
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON, forcedTop: Bool = false) {
        let resolvedID = json.id.exists ? json.id.identifier : json.entityId.identifier
        id = resolvedID
        uid = json.uid.identifier
        username = json.username.string
        avatar = coolapkNormalizedURL(json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string)
        message = json.message.string
        replyToName = json.rusername.string
        replyToID = json.rid.identifier
        rootID = json.rrid.identifier
        dateline = json.dateline.date
        datelineText = json.dateline_text.string
        likeNum = json.likenum.int
        replyNum = json.replynum.int
        isLiked = json.userAction.like.int > 0
        isAuthor = json.is_feed_author.int > 0 || json.isAuthor.int > 0
        isTop = forcedTop || json.is_top.int > 0 || json.isTop.int > 0
        mediaItems = FeedMedia.from(json: json, contentId: resolvedID, contentType: .reply)
        pics = mediaItems.map(\.sourceUrl)
        nested = json.replyRows.array
            .filter { Self.isValidReplyJSON($0) }
            .map { ReplyItem(json: $0) }
        ipLocation = json.ip_location.string
    }

    public static func isValidReplyJSON(_ json: JSON) -> Bool {
        let entityType = json.entityType.string.lowercased()
        let template = json.entityTemplate.string.lowercased()
        if entityType == "card" || entityType.contains("ad") || entityType.contains("sponsor") {
            return false
        }
        if template.contains("ad") || template.contains("sponsor") || json.is_ad.int > 0 {
            return false
        }
        let hasText = !json.message.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMedia = !json.pic.string.isEmpty || !json.picArr.array.isEmpty || !json.imageUriList.array.isEmpty || !json.image_uri_list.array.isEmpty
        let hasUser = !json.username.string.isEmpty || !json.uid.identifier.isEmpty
        return (hasText || hasMedia) && hasUser
    }
}

public struct FeedItem: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case feed
        case feedArticle
        case product
        case topic
        case question
        case vote
        case dyh
        case unknown
    }

    public let id: String
    public var kind: Kind
    public var uid: String
    public var username: String
    public var avatar: String
    public var message: String
    public var messageTitle: String
    public var title: String
    public var deviceTitle: String
    public var ipLocation: String
    public var dateline: Date?
    public var datelineText: String
    public var likeNum: Int
    public var commentNum: Int
    public var replyNum: Int
    public var forwardNum: Int
    public var favNum: Int
    public var shareNum: Int
    public var pics: [String]
    public var mediaItems: [FeedMedia]
    public var cover: String
    public var isLiked: Bool
    public var isFavorited: Bool
    public var isHeadline: Bool
    public var infoText: String
    public var feedTypeName: String
    public var feedType: String
    public var targetTitle: String
    public var targetURL: String
    public var targetPic: String
    public var targetInfo: String
    public var forwardSourceName: String
    public var replyRows: [ReplyItem]
    public var topReplyRows: [ReplyItem]
    public var sourceFeed: ForwardedContent?
    public var rankScore: Int
    public var articleParts: [FeedArticlePart]
    public var vote: VoteInfo?
    public var questionAnswerNum: Int
    public var topicTags: [String]
    public var topicIDs: [String]
    public var changeCount: Int

    public static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id && lhs.isLiked == rhs.isLiked && lhs.likeNum == rhs.likeNum && lhs.isFavorited == rhs.isFavorited && lhs.favNum == rhs.favNum && lhs.replyNum == rhs.replyNum
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON) {
        let resolvedID = json.id.exists ? json.id.identifier : json.entityId.identifier
        id = resolvedID
        uid = json.uid.identifier
        username = json.username.string
        avatar = coolapkNormalizedURL(json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string)
        message = json.message.string
        messageTitle = json.message_title.string
        title = json.title.string
        deviceTitle = json.device_title.string
        ipLocation = json.ip_location.string
        dateline = json.dateline.date ?? json.lastupdate.date
        datelineText = json.dateline_text.string
        likeNum = json.likenum.int
        commentNum = json.commentnum.int
        replyNum = json.replynum.int
        forwardNum = json.forwardnum.int
        favNum = json.favnum.int
        shareNum = json.share_num.int
        cover = coolapkNormalizedURL(json.message_cover.string)
        isHeadline = json.is_headline.int > 0
        infoText = json.infoHtml.string.isEmpty ? json.info.string : json.infoHtml.string
        feedTypeName = json.feedTypeName.string.isEmpty ? "动态" : json.feedTypeName.string
        rankScore = json.rank_score.int
        questionAnswerNum = json.question_answer_num.int
        changeCount = json.change_count.int

        let parsedType = json.feedType.string
        feedType = parsedType.isEmpty ? "feed" : parsedType
        let isArticle = parsedType == "feedArticle" || json.is_html_article.int > 0

        let rawOutput = json.message_raw_output
        let outputArray = rawOutput.array.isEmpty ? rawOutput.parsed.array : rawOutput.array
        articleParts = outputArray.enumerated().map { FeedArticlePart(json: $0.element, index: $0.offset) }

        mediaItems = FeedMedia.from(
            json: json,
            contentId: resolvedID,
            contentType: isArticle ? .article : .feed
        )
        pics = mediaItems.map(\.sourceUrl)

        isLiked = json.userAction.like.int > 0
        isFavorited = json.userAction.favorite.int > 0 || json.userAction.collect.int > 0

        switch feedType {
        case "feedArticle": kind = .feedArticle
        case "product": kind = .product
        case "topic": kind = .topic
        case "question": kind = .question
        case "vote": kind = .vote
        case "dyh", "dyhArticle": kind = .dyh
        case "feed": kind = isArticle ? .feedArticle : .feed
        default: kind = parsedType.isEmpty ? .feed : .unknown
        }

        if json.targetRow.exists, !json.targetRow.isNull {
            targetTitle = json.targetRow.title.string
            targetURL = json.targetRow.url.string
            targetPic = coolapkNormalizedURL(json.targetRow.logo.string.isEmpty ? json.targetRow.pic.string : json.targetRow.logo.string)
            targetInfo = json.targetRow.description.string
        } else {
            targetTitle = ""
            targetURL = ""
            targetPic = ""
            targetInfo = ""
        }
        if targetTitle.isEmpty, !json.ttitle.string.isEmpty {
            targetTitle = json.ttitle.string
            targetURL = json.turl.string
            targetPic = coolapkNormalizedURL(json.tpic.string)
        }
        if targetTitle.isEmpty, !json.topic_title.string.isEmpty {
            targetTitle = json.topic_title.string
        }

        if json.sourceFeed.exists, !json.sourceFeed.isNull {
            forwardSourceName = json.sourceFeed.username.string
            sourceFeed = ForwardedContent(json: json.sourceFeed)
        } else {
            forwardSourceName = ""
            sourceFeed = nil
        }
        if !json.forwardSourceName.string.isEmpty {
            forwardSourceName = json.forwardSourceName.string
        }

        replyRows = json.replyRows.array.map { ReplyItem(json: $0) }
        topReplyRows = json.topReplyRows.array.map { ReplyItem(json: $0, forcedTop: true) }
        vote = VoteInfo(json: json.vote)

        var tags: [String] = []
        for item in json.tags.array {
            let value = item.string
            if !value.isEmpty { tags.append(value) }
        }
        if tags.isEmpty, !json.tags.string.isEmpty {
            tags = json.tags.string.split(separator: ",").map(String.init)
        }
        if !targetTitle.isEmpty, !tags.contains(targetTitle) {
            tags.append(targetTitle)
        }
        topicTags = tags

        var tIDs: [String] = []
        if !json.tid.identifier.isEmpty { tIDs.append(json.tid.identifier) }
        for rel in json.relationRows.array {
            let rid = rel.entityId.identifier
            if !rid.isEmpty { tIDs.append(rid) }
        }
        topicIDs = tIDs
    }

    public var forwardLabel: String {
        sourceFeed != nil ? "转发动态" : ""
    }
}
