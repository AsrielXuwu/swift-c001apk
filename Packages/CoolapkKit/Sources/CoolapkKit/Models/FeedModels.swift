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
        let normalizedSource = coolapkNormalizedURL(sourceUrl)
        let normalizedPreview = previewUrl.map(coolapkNormalizedURL)
        let normalizedVideo = videoUrl.map(coolapkNormalizedURL)
        self.sourceUrl = normalizedSource
        self.previewUrl = normalizedPreview
        self.videoUrl = normalizedVideo
        let hintedLive = Self.hasLiveURLHint(normalizedSource) || (normalizedPreview.map(Self.hasLiveURLHint) ?? false)
        let hintedHDR = Self.hasHDRURLHint(normalizedSource) || (normalizedPreview.map(Self.hasHDRURLHint) ?? false)
        self.isLivePhoto = isLivePhoto || (normalizedVideo?.isEmpty == false) || hintedLive
        self.isHdr = isHdr || hintedHDR
        self.contentId = contentId
        self.contentType = contentType
    }

    public static func hasLiveURLHint(_ url: String) -> Bool {
        url.range(of: "-livepic", options: .caseInsensitive) != nil
    }

    public static func hasHDRURLHint(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("-uhdr") || lower.contains("-xhdr")
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
        if !result.isEmpty {
            var seen = Set<String>()
            return result.filter { seen.insert($0.id).inserted }
        }

        let pictures = json.picArr.array.map(\.string).filter { !$0.isEmpty }
        if !pictures.isEmpty {
            var seen = Set<String>()
            return pictures.map { FeedMedia(sourceUrl: $0, contentId: contentId, contentType: contentType) }
                .filter { seen.insert($0.id).inserted }
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

    public var hasVisibleContent: Bool {
        let stripped = FeedHTMLParser.plainText(message)
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !stripped.isEmpty || !mediaItems.isEmpty
    }

    public static func isValidReplyJSON(_ json: JSON) -> Bool {
        let entityType = json.entityType.string.lowercased()
        let template = json.entityTemplate.string.lowercased()
        if !entityType.isEmpty && entityType != "feed_reply" && entityType != "reply" {
            return false
        }
        if template.contains("ad")
            || template.contains("sponsor")
            || template.contains("card")
            || json.is_ad.int > 0
            || json.ad.exists
            || json.adInfo.exists
            || json.ad_info.exists
            || !json.ad_url.string.isEmpty
            || json.block_status.int != 0 {
            return false
        }
        let stripped = FeedHTMLParser.plainText(json.message.string)
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMedia = !json.pic.string.isEmpty
            || !json.picArr.array.isEmpty
            || !json.imageUriList.array.isEmpty
            || !json.image_uri_list.array.isEmpty
        let hasUser = !json.username.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !json.uid.identifier.isEmpty
        return (!stripped.isEmpty || hasMedia) && hasUser
    }
}

public struct FeedRelationEntity: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var title: String
    public var url: String
    public var pic: String
    public var entityType: String

    public init(
        id: String,
        title: String,
        url: String,
        pic: String = "",
        entityType: String = ""
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.pic = pic
        self.entityType = entityType
    }
}

public struct FeedExtraLink: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public var title: String
    public var url: String
    public var pic: String
    public var subtitle: String
    public var isTradeLink: Bool

    public init(
        id: String,
        title: String,
        url: String,
        pic: String = "",
        subtitle: String = "",
        isTradeLink: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.pic = pic
        self.subtitle = subtitle
        self.isTradeLink = isTradeLink
    }
}

public struct FeedRatingDimension: Identifiable, Hashable, Sendable, Codable {
    public var id: String { name }
    public var name: String
    public var score: Double

    public init(name: String, score: Double) {
        self.name = name
        self.score = score
    }

    public static func parseList(from json: JSON) -> [FeedRatingDimension] {
        let candidates: [JSON] = [
            json.rating_item_info.parsed.exists ? json.rating_item_info.parsed : json.rating_item_info,
            json.ratingItemInfo.parsed.exists ? json.ratingItemInfo.parsed : json.ratingItemInfo,
            json.extraDataArr.rating_item_info.parsed.exists ? json.extraDataArr.rating_item_info.parsed : json.extraDataArr.rating_item_info,
            json.extraData.parsed.rating_item_info
        ]
        for candidate in candidates {
            let arr = candidate.array
            guard !arr.isEmpty else { continue }
            var results: [FeedRatingDimension] = []
            var seen = Set<String>()
            for item in arr {
                let name = [
                    item.name.string,
                    item.title.string,
                    item.label.string,
                    item.key.string,
                    item.item_name.string
                ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rawScore = [
                    item.score.double,
                    item.value.double,
                    item.rating_score.double,
                    item.star_score.double
                ].first { $0 > 0 } ?? 0
                guard !name.isEmpty, rawScore > 0, seen.insert(name).inserted else { continue }
                let normalized = rawScore <= 5.0 ? (rawScore * 2.0) : min(10.0, rawScore)
                results.append(FeedRatingDimension(name: name, score: normalized))
            }
            if !results.isEmpty {
                return results
            }
        }
        return []
    }
}

public struct FeedRatingInfo: Hashable, Sendable, Codable {
    public var scoreOutOf10: Double
    public var starCount: Int
    public var targetTitle: String
    public var targetLogo: String
    public var targetURL: String
    public var prosText: String
    public var consText: String
    public var summaryText: String
    public var additionText: String
    public var isOwner: Bool
    public var dimensions: [FeedRatingDimension]

    public init(
        scoreOutOf10: Double,
        starCount: Int,
        targetTitle: String = "",
        targetLogo: String = "",
        targetURL: String = "",
        prosText: String = "",
        consText: String = "",
        summaryText: String = "",
        additionText: String = "",
        isOwner: Bool = false,
        dimensions: [FeedRatingDimension] = []
    ) {
        self.scoreOutOf10 = scoreOutOf10
        self.starCount = starCount
        self.targetTitle = targetTitle
        self.targetLogo = targetLogo
        self.targetURL = targetURL
        self.prosText = prosText
        self.consText = consText
        self.summaryText = summaryText
        self.additionText = additionText
        self.isOwner = isOwner
        self.dimensions = dimensions
    }

    public static func from(json: JSON, targetTitle: String, targetLogo: String, targetURL: String) -> FeedRatingInfo? {
        let lowerType = json.feedType.string.lowercased()
        let lowerEntityType = json.entityType.string.lowercased()
        let lowerTemplate = json.entityTemplate.string.lowercased()
        let isExplicitRatingType = lowerType == "rating"
            || lowerType == "ratingfeed"
            || lowerType == "feed_rating"
            || lowerType == "noderating"
            || lowerEntityType == "rating"
            || lowerEntityType == "ratingfeed"
            || lowerEntityType == "feed_rating"
            || lowerEntityType == "noderating"
            || lowerTemplate.contains("rating")

        let rawScoreCandidates: [Double] = [
            json.rating_score.double,
            json.ratingScore.double,
            json.star_score.double,
            json.starScore.double,
            json.rating_star.double,
            json.extraDataArr.rating_score.double,
            json.extraData.parsed.rating_score.double,
            isExplicitRatingType ? json.score.double : 0,
            isExplicitRatingType ? json.star.double : 0
        ]
        let rawScore = rawScoreCandidates.first { $0 > 0 } ?? 0

        let v4Raw = json.v4_rating_message.exists ? json.v4_rating_message : json.v4RatingMessage
        let v4Obj = v4Raw.isObject ? v4Raw : v4Raw.parsed
        let pros = [
            json.comment_good.string,
            json.commentGood.string,
            v4Obj.comment_good.string,
            v4Obj.pros.string,
            v4Obj.good.string
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

        let cons = [
            json.comment_bad.string,
            json.commentBad.string,
            v4Obj.comment_bad.string,
            v4Obj.cons.string,
            v4Obj.bad.string
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

        let summary = [
            json.comment_general.string,
            json.commentGeneral.string,
            v4Obj.comment_general.string,
            v4Obj.summary.string,
            v4Obj.general.string
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

        let addition = [
            json.comment_addition.string,
            json.commentAddition.string,
            v4Obj.comment_addition.string
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

        let dims = FeedRatingDimension.parseList(from: json)

        guard isExplicitRatingType || rawScore > 0 || !pros.isEmpty || !cons.isEmpty || !summary.isEmpty || !dims.isEmpty else {
            return nil
        }

        let score10: Double
        let stars: Int
        if rawScore > 0 {
            if rawScore <= 5.0 {
                score10 = min(10.0, rawScore * 2.0)
                stars = max(1, min(5, Int( rawScore.rounded() )))
            } else {
                score10 = min(10.0, rawScore)
                stars = max(1, min(5, Int( (rawScore / 2.0).rounded() )))
            }
        } else {
            score10 = 0
            stars = 0
        }

        let ownerFlag = json.buy_status.int > 0
            || json.buyStatus.int > 0
            || json.is_owner.int > 0
            || json.isOwner.int > 0
            || json.buy_status.bool
            || json.is_owner.bool

        return FeedRatingInfo(
            scoreOutOf10: score10,
            starCount: stars,
            targetTitle: targetTitle,
            targetLogo: targetLogo,
            targetURL: targetURL,
            prosText: pros,
            consText: cons,
            summaryText: summary,
            additionText: addition,
            isOwner: ownerFlag,
            dimensions: dims
        )
    }
}

public struct FeedVideoInfo: Hashable, Sendable, Codable {
    public var url: String
    public var coverURL: String
    public var durationSeconds: Int
    public var title: String
    public var isExternalPage: Bool

    public init(
        url: String,
        coverURL: String = "",
        durationSeconds: Int = 0,
        title: String = "",
        isExternalPage: Bool = false
    ) {
        self.url = coolapkNormalizedURL(url)
        self.coverURL = coolapkNormalizedURL(coverURL)
        self.durationSeconds = durationSeconds
        self.title = title
        self.isExternalPage = isExternalPage
    }

    public var formattedDuration: String {
        guard durationSeconds > 0 else { return "" }
        let mins = durationSeconds / 60
        let secs = durationSeconds % 60
        if mins >= 60 {
            let hrs = mins / 60
            let remMins = mins % 60
            return String(format: "%d:%02d:%02d", hrs, remMins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    public static func from(json: JSON, extraObjects: [JSON]) -> FeedVideoInfo? {
        let mediaInfo = json.media_info.isObject ? json.media_info : json.media_info.parsed
        let videoInfo = json.video_info.isObject ? json.video_info : json.video_info.parsed
        let extraData = json.extraDataArr.isObject ? json.extraDataArr : json.extraData.parsed

        let isVideoContext = json.feedType.string.lowercased() == "video"
            || json.media_type.string.lowercased() == "video"
            || json.mediaType.string.lowercased() == "video"
            || mediaInfo.type.string.lowercased() == "video"
            || !json.video_url.string.isEmpty
            || !json.videoUrl.string.isEmpty
            || !videoInfo.url.string.isEmpty

        var rawVideoURL = [
            json.video_url.string,
            json.videoUrl.string,
            videoInfo.url.string,
            videoInfo.video_url.string,
            videoInfo.play_url.string,
            mediaInfo.video_url.string,
            mediaInfo.videoUrl.string,
            extraData.video_url.string,
            extraData.videoUrl.string,
            isVideoContext ? json.media_url.string : "",
            isVideoContext ? mediaInfo.url.string : ""
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

        if rawVideoURL.isEmpty {
            for obj in extraObjects {
                let candidate = [
                    obj.video_url.string,
                    obj.videoUrl.string,
                    obj.play_url.string,
                    obj.playUrl.string
                ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
                if !candidate.isEmpty {
                    rawVideoURL = candidate
                    break
                }
            }
        }

        let unwrapped = FeedItem.unwrapCoolapkRedirectURL(rawVideoURL).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unwrapped.isEmpty else { return nil }
        let lower = unwrapped.lowercased()
        let isPlayableStream = lower.contains(".mp4")
            || lower.contains(".m3u8")
            || lower.contains(".mov")
            || lower.contains("video")
        let isKnownVideoSite = lower.contains("bilibili.com")
            || lower.contains("b23.tv")
            || lower.contains("douyin.com")
            || lower.contains("youtu.be")
            || lower.contains("youtube.com")
        guard isVerticalOrVideo(isVideoContext: isVideoContext, isPlayableStream: isPlayableStream, isKnownVideoSite: isKnownVideoSite) else {
            return nil
        }

        let cover = [
            json.video_pic.string,
            json.videoPic.string,
            json.media_pic.string,
            json.mediaPic.string,
            videoInfo.pic.string,
            videoInfo.cover.string,
            mediaInfo.pic.string,
            mediaInfo.cover.string,
            extraData.video_pic.string,
            json.message_cover.string,
            json.pic.string
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

        let duration = [
            json.video_duration.int,
            json.videoDuration.int,
            videoInfo.duration.int,
            mediaInfo.duration.int,
            extraData.video_duration.int
        ].first { $0 > 0 } ?? 0

        let title = [
            videoInfo.title.string,
            mediaInfo.title.string,
            json.extra_title.string,
            json.message_title.string
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""

        return FeedVideoInfo(
            url: unwrapped,
            coverURL: cover,
            durationSeconds: duration,
            title: title,
            isExternalPage: !isPlayableStream
        )
    }

    private static func isVerticalOrVideo(isVideoContext: Bool, isPlayableStream: Bool, isKnownVideoSite: Bool) -> Bool {
        isVideoContext || isPlayableStream || isKnownVideoSite
    }
}

public struct FeedItem: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case feed
        case feedArticle
        case product
        case topic
        case question
        case answer
        case vote
        case dyh
        case ershou
        case rating
        case unknown
    }

    public let id: String
    public var targetFeedID: String
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
    public var authorLoginTime: Date?
    public var isAuthorFollowed: Bool
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
    public var extraTitle: String
    public var extraURL: String
    public var extraPic: String
    public var extraInfo: String
    public var priceText: String
    public var originalPriceText: String
    public var cityText: String
    public var dealStatusText: String
    public var xianyuURL: String
    public var extraLinks: [FeedExtraLink]
    public var forwardSourceName: String
    public var replyRows: [ReplyItem]
    public var topReplyRows: [ReplyItem]
    public var sourceFeed: ForwardedContent?
    public var rankScore: Int
    public var articleParts: [FeedArticlePart]
    public var vote: VoteInfo?
    public var questionID: String
    public var questionTitle: String
    public var questionAnswerNum: Int
    public var topicTags: [String]
    public var topicIDs: [String]
    public var relationEntities: [FeedRelationEntity]
    public var changeCount: Int
    public var totalPicCount: Int
    public var isTruncated: Bool
    public var subTabID: String
    public var subTabBadgeText: String
    public var readNum: Int
    public var isSelfOnly: Bool
    public var isModified: Bool
    public var ratingInfo: FeedRatingInfo?
    public var videoInfo: FeedVideoInfo?

    public var effectiveFeedID: String {
        let candidate = (targetFeedID.isEmpty || targetFeedID == "0") ? id : targetFeedID
        return candidate == "0" ? "" : candidate
    }

    public var needsDetailRefresh: Bool {
        if kind == .feedArticle && articleParts.isEmpty { return true }
        if kind == .vote && vote == nil { return true }
        if isTruncated || message.contains("查看更多") { return true }
        if totalPicCount > mediaItems.count { return true }
        if subTabID == "6" && priceText.isEmpty { return true }
        return false
    }

    public var isSecondHand: Bool {
        kind == .ershou
            || feedType == "ershou"
            || Self.containsTradeKeyword(feedTypeName)
            || Self.containsTradeKeyword(targetTitle)
            || !xianyuURL.isEmpty
            || topicTags.contains { Self.containsTradeKeyword($0) }
            || relationEntities.contains { Self.containsTradeKeyword($0.title) }
    }

    public var hasPriceDisplay: Bool {
        isSecondHand || !priceText.isEmpty
    }

    public var resolvedExtraLinks: [FeedExtraLink] {
        if !extraLinks.isEmpty {
            return extraLinks
        }
        return Self.buildExtraLinks(
            primaryTitle: extraTitle,
            primaryURL: extraURL,
            primaryPic: extraPic,
            primaryInfo: extraInfo,
            xianyuURL: xianyuURL,
            extraObjects: [],
            messageHTML: message,
            isSecondHand: isSecondHand
        )
    }

    public static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
            && lhs.isLiked == rhs.isLiked
            && lhs.likeNum == rhs.likeNum
            && lhs.isFavorited == rhs.isFavorited
            && lhs.favNum == rhs.favNum
            && lhs.replyNum == rhs.replyNum
            && lhs.isAuthorFollowed == rhs.isAuthorFollowed
            && lhs.authorLoginTime == rhs.authorLoginTime
            && lhs.messageTitle == rhs.messageTitle
            && lhs.message == rhs.message
            && lhs.isTruncated == rhs.isTruncated
            && lhs.articleParts.count == rhs.articleParts.count
            && lhs.mediaItems.count == rhs.mediaItems.count
            && lhs.totalPicCount == rhs.totalPicCount
            && (lhs.vote == nil) == (rhs.vote == nil)
            && lhs.priceText == rhs.priceText
            && lhs.dealStatusText == rhs.dealStatusText
            && lhs.extraURL == rhs.extraURL
            && lhs.xianyuURL == rhs.xianyuURL
            && lhs.extraLinks == rhs.extraLinks
            && lhs.subTabBadgeText == rhs.subTabBadgeText
            && lhs.readNum == rhs.readNum
            && lhs.isSelfOnly == rhs.isSelfOnly
            && lhs.isModified == rhs.isModified
            && lhs.ratingInfo == rhs.ratingInfo
            && lhs.videoInfo == rhs.videoInfo
    }

    public mutating func mergePreservedMetadata(from fallback: FeedItem) {
        if priceText.isEmpty && !fallback.priceText.isEmpty {
            priceText = fallback.priceText
        }
        if originalPriceText.isEmpty && !fallback.originalPriceText.isEmpty {
            originalPriceText = fallback.originalPriceText
        }
        if dealStatusText.isEmpty && !fallback.dealStatusText.isEmpty {
            dealStatusText = fallback.dealStatusText
        }
        if subTabID.isEmpty && !fallback.subTabID.isEmpty {
            subTabID = fallback.subTabID
        }
        if subTabBadgeText.isEmpty && !fallback.subTabBadgeText.isEmpty {
            subTabBadgeText = fallback.subTabBadgeText
        }
        if ratingInfo == nil, let fbRating = fallback.ratingInfo {
            ratingInfo = fbRating
        }
        if videoInfo == nil, let fbVideo = fallback.videoInfo {
            videoInfo = fbVideo
        }
        if readNum == 0 && fallback.readNum > 0 {
            readNum = fallback.readNum
        }
        if !isSelfOnly && fallback.isSelfOnly {
            isSelfOnly = true
        }
        if !isModified && fallback.isModified {
            isModified = true
        }
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON) {
        let rawResolvedID = json.id.exists ? json.id.identifier : json.entityId.identifier
        let nonZeroResolvedID = rawResolvedID == "0" ? "" : rawResolvedID
        let rawEntityType = json.entityType.string.lowercased()
        let explicitFeedID = [json.feed_id.identifier, json.feedId.identifier]
            .first { !$0.isEmpty && $0 != "0" }
            ?? (!rawEntityType.isEmpty && rawEntityType != "feed"
                ? [json.fid.identifier, json.target_id.identifier].first { !$0.isEmpty && $0 != "0" }
                : nil)
            ?? Self.extractFeedIDFromURL(json.url.string)
            ?? ""
        let isCollectionItemWrapper = rawEntityType.contains("collection")
        let resolvedID = (isCollectionItemWrapper && !explicitFeedID.isEmpty)
            ? explicitFeedID
            : (!nonZeroResolvedID.isEmpty ? nonZeroResolvedID : explicitFeedID)
        id = resolvedID
        targetFeedID = (!explicitFeedID.isEmpty && !rawEntityType.isEmpty && rawEntityType != "feed")
            ? explicitFeedID
            : resolvedID
        uid = json.uid.identifier.isEmpty ? json.userInfo.uid.identifier : json.uid.identifier
        username = json.username.string.isEmpty ? json.userInfo.username.string : json.username.string
        avatar = coolapkNormalizedURL(
            [json.userAvatar.string, json.avatar.string, json.userInfo.userAvatar.string].first { !$0.isEmpty } ?? ""
        )
        message = json.message.string
        messageTitle = json.message_title.string
        title = json.title.string
        deviceTitle = json.device_title.string
        ipLocation = json.ip_location.string
        dateline = json.dateline.date ?? json.lastupdate.date
        datelineText = json.dateline_text.string
        authorLoginTime = json.userInfo.logintime.date ?? json.logintime.date
        let followAuthorFlag = json.userAction.followAuthor.exists
            ? json.userAction.followAuthor
            : (json.userInfo.isFollowed.exists ? json.userInfo.isFollowed : json.userAction.follow)
        isAuthorFollowed = followAuthorFlag.bool || followAuthorFlag.int > 0
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
        let parsedType = json.feedType.string
        let extraDataObj = json.extraData.parsed.isObject ? json.extraData.parsed : (json.extraData.isObject ? json.extraData : JSON.null)
        let extraQAnswerNum = extraDataObj.questionAnswerNum.int
        questionAnswerNum = json.question_answer_num.int > 0 ? json.question_answer_num.int : extraQAnswerNum
        let rawQuestionURL = !json.questionUrl.string.isEmpty ? json.questionUrl.string : extraDataObj.questionUrl.string
        let extractedQID = Self.extractFeedIDFromURL(rawQuestionURL) ?? ""
        if parsedType == "answer" || !extractedQID.isEmpty || json.type.int == 11 {
            let fidCandidate = json.fid.identifier
            questionID = !extractedQID.isEmpty ? extractedQID : ((fidCandidate.isEmpty || fidCandidate == "0" || fidCandidate == resolvedID) ? "" : fidCandidate)
        } else {
            questionID = ""
        }
        questionTitle = !extraDataObj.questionTitle.string.isEmpty
            ? extraDataObj.questionTitle.string
            : ((!questionID.isEmpty && !json.message_title.string.isEmpty) ? json.message_title.string : (!questionID.isEmpty ? json.title.string : ""))
        changeCount = json.change_count.int

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
        let declaredPicTotal = [json.pic_count.int, json.pic_num.int].max() ?? 0
        totalPicCount = declaredPicTotal > max(mediaItems.count, json.picArr.array.count)
            ? declaredPicTotal
            : mediaItems.count
        isTruncated = json.is_truncated.bool
            || json.issummary.int > 0
            || json.message.string.contains("查看更多")
            || (isArticle && outputArray.isEmpty)

        isLiked = json.userAction.like.int > 0
        isFavorited = json.userAction.favorite.int > 0 || json.userAction.collect.int > 0

        let resolvedExtraTitle = json.extra_title.string
        let resolvedExtraURL = Self.unwrapCoolapkRedirectURL(json.extra_url.string)
        let resolvedExtraPic = coolapkNormalizedURL(json.extra_pic.string)
        let resolvedExtraInfo = json.extra_info.string

        let extraObjects = Self.collectAllExtraObjects(from: json, articleOutputArray: outputArray)
        let extraTitleFromObj = extraObjects.compactMap { obj in
            [
                obj.product_title.string,
                obj.productTitle.string,
                obj.title.string,
                obj.extra_title.string,
                obj.goods_title.string,
                obj.name.string
            ].first { !$0.isEmpty }
        }.first ?? ""
        let extraURLFromObj = extraObjects.compactMap { obj in
            [
                obj.link_url.string,
                obj.linkUrl.string,
                obj.xianyu_url.string,
                obj.goofish_url.string,
                obj.ershou_url.string,
                obj.trade_url.string,
                obj.jump_url.string,
                obj.buy_url.string,
                obj.sell_url.string,
                obj.item_url.string,
                obj.extra_url.string,
                obj.url.string,
                obj.link.string,
                obj.target_url.string
            ].first { !$0.isEmpty }
        }.first.map(Self.unwrapCoolapkRedirectURL) ?? ""
        let extraPicFromObj = extraObjects.compactMap { obj in
            [obj.pic.string, obj.extra_pic.string, obj.cover.string, obj.logo.string].first { !$0.isEmpty }
        }.first.map(coolapkNormalizedURL) ?? ""
        let extraInfoFromObj = extraObjects.compactMap { obj in
            [
                obj.link_source.string,
                obj.linkSource.string,
                obj.platform.string,
                obj.info.string,
                obj.extra_info.string,
                obj.sub_title.string,
                obj.status_text.string
            ].first { !$0.isEmpty }
        }.first ?? ""

        let effectiveExtraTitle = resolvedExtraTitle.isEmpty ? extraTitleFromObj : resolvedExtraTitle
        let fallbackTopURL = Self.unwrapCoolapkRedirectURL([json.link_url.string, json.media_url.string, json.target_url.string].first { !$0.isEmpty } ?? "")
        let effectiveExtraURL = !resolvedExtraURL.isEmpty ? resolvedExtraURL : (!extraURLFromObj.isEmpty ? extraURLFromObj : fallbackTopURL)
        extraTitle = effectiveExtraTitle
        extraURL = effectiveExtraURL
        extraPic = resolvedExtraPic.isEmpty ? extraPicFromObj : resolvedExtraPic
        extraInfo = resolvedExtraInfo.isEmpty ? extraInfoFromObj : resolvedExtraInfo

        let resolvedSubTabID = ([
            json.tsubid.identifier,
            json.tsub_id.identifier,
            json.subId.identifier,
            json.sub_id.identifier,
            json.target_sub_id.identifier,
            json.targetSubId.identifier,
            json.subTypeId.identifier,
            json.sub_type_id.identifier
        ] + extraObjects.flatMap { obj in
            [
                obj.tsubid.identifier,
                obj.tsub_id.identifier,
                obj.subId.identifier,
                obj.sub_id.identifier,
                obj.target_sub_id.identifier,
                obj.targetSubId.identifier,
                obj.subTypeId.identifier,
                obj.sub_type_id.identifier
            ]
        }).first { !$0.isEmpty && $0 != "0" } ?? ""
        subTabID = resolvedSubTabID

        let rawSubDataScalar = [
            json.tsubdata.string,
            json.tsub_data.string,
            json.subData.string,
            json.sub_data.string,
            json.target_sub_data.string,
            json.targetSubData.string,
            json.subTabData.string,
            json.sub_tab_data.string
        ].first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let skuConfigName = ([
            json.config_name.string,
            json.configName.string,
            json.version_name.string,
            json.versionName.string,
            json.sku_name.string,
            json.skuName.string
        ] + extraObjects.flatMap { obj in
            [
                obj.config_name.string,
                obj.configName.string,
                obj.version_name.string,
                obj.versionName.string,
                obj.sku_name.string,
                obj.skuName.string
            ]
        }).first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let isFaceDeal = ([
            json.is_face_deal,
            json.isFaceDeal,
            json.ershou_info.is_face_deal,
            json.ershou_info.parsed.is_face_deal,
            json.ershouInfo.is_face_deal,
            json.ershouInfo.parsed.is_face_deal
        ] + extraObjects.flatMap { [$0.is_face_deal, $0.isFaceDeal] })
            .contains { $0.bool || $0.int == 1 }

        let explicitPriceNodes: [JSON] = [
            json.final_price,
            json.finalPrice,
            json.hand_price,
            json.handPrice,
            json.daoshou_price,
            json.daoshouPrice,
            json.ershou_price,
            json.ershouPrice,
            json.product_price,
            json.productPrice,
            json.buy_price,
            json.buyPrice,
            json.real_price,
            json.realPrice,
            json.pay_price,
            json.payPrice,
            json.order_price,
            json.orderPrice,
            json.discount_price,
            json.discountPrice,
            json.deal_price,
            json.dealPrice,
            json.trade_price,
            json.tradePrice,
            json.sell_price,
            json.sellPrice,
            json.goods_promo_price,
            json.goodsPromoPrice,
            json.product_goods_price,
            json.productGoodsPrice,
            json.goods_price,
            json.goodsPrice,
            json.show_price,
            json.showPrice,
            json.item_price,
            json.itemPrice,
            json.sale_price,
            json.salePrice,
            json.current_price,
            json.currentPrice,
            json.rmb_price,
            json.rmbPrice,
            json.price,
            json.price_text,
            json.priceText,
            json.price_str,
            json.priceStr
        ] + extraObjects.flatMap { obj in
            [
                obj.final_price,
                obj.finalPrice,
                obj.hand_price,
                obj.handPrice,
                obj.daoshou_price,
                obj.daoshouPrice,
                obj.ershou_price,
                obj.ershouPrice,
                obj.product_price,
                obj.productPrice,
                obj.buy_price,
                obj.buyPrice,
                obj.real_price,
                obj.realPrice,
                obj.pay_price,
                obj.payPrice,
                obj.order_price,
                obj.orderPrice,
                obj.discount_price,
                obj.discountPrice,
                obj.deal_price,
                obj.dealPrice,
                obj.trade_price,
                obj.tradePrice,
                obj.sell_price,
                obj.sellPrice,
                obj.goods_promo_price,
                obj.goodsPromoPrice,
                obj.product_goods_price,
                obj.productGoodsPrice,
                obj.goods_price,
                obj.goodsPrice,
                obj.show_price,
                obj.showPrice,
                obj.item_price,
                obj.itemPrice,
                obj.sale_price,
                obj.salePrice,
                obj.current_price,
                obj.currentPrice,
                obj.rmb_price,
                obj.rmbPrice,
                obj.price,
                obj.price_text,
                obj.priceText,
                obj.price_str,
                obj.priceStr
            ]
        }

        var parsedPriceNum = explicitPriceNodes.lazy.map(Self.parseNumericPrice).first { $0 > 0 } ?? 0
        if parsedPriceNum <= 0 {
            parsedPriceNum = Self.extractDynamicPriceFromExtraObjects(
                json: json,
                extraObjects: extraObjects,
                subTabID: resolvedSubTabID,
                rawSubDataScalar: rawSubDataScalar
            )
        }

        let rawPriceString = explicitPriceNodes.lazy
            .map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "0" && $0 != "0.0" && $0 != "0.00" } ?? ""

        let relationURLs = json.relationRows.array.map(\.url.string).filter { !$0.isEmpty }
        let linkCandidates = ([
            json.xianyu_url.string,
            json.goofish_url.string,
            json.ershou_url.string,
            json.trade_url.string,
            json.link_url.string,
            effectiveExtraURL,
            json.media_url.string,
            json.target_url.string
        ] + extraObjects.flatMap { obj in
            [
                obj.link_url.string,
                obj.linkUrl.string,
                obj.xianyu_url.string,
                obj.goofish_url.string,
                obj.ershou_url.string,
                obj.trade_url.string,
                obj.jump_url.string,
                obj.buy_url.string,
                obj.url.string,
                obj.link.string
            ]
        } + relationURLs)
        .map(Self.unwrapCoolapkRedirectURL)
        .filter { !$0.isEmpty }

        let articlePartsText = outputArray.map {
            [$0.title.string, FeedHTMLParser.plainText($0.message.string), $0.description.string, $0.subTitle.string]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }.joined(separator: " ")
        let plainBody = FeedHTMLParser.plainText(json.message.string)
        let matchedCandidate = linkCandidates.first { Self.isXianyuOrTradeURL($0) }
        if let matchedCandidate {
            xianyuURL = matchedCandidate
        } else {
            xianyuURL = Self.extractFirstXianyuURL(in: json.message.string + " " + plainBody + " " + articlePartsText + " " + effectiveExtraURL + " " + resolvedExtraInfo) ?? ""
        }

        let relationTitles = json.relationRows.array.map(\.title.string)
            + json.extraRows.array.map(\.title.string)
            + json.productRows.array.map(\.title.string)
        let extraDescriptiveTexts = extraObjects.flatMap { obj in
            [
                obj.title.string,
                obj.sub_title.string,
                obj.subTitle.string,
                obj.description.string,
                obj.info.string,
                FeedHTMLParser.plainText(obj.infoHtml.string),
                obj.text.string,
                obj.label.string,
                obj.name.string,
                obj.value.string,
                obj.extra_title.string,
                obj.extra_info.string,
                obj.config_name.string,
                obj.configName.string
            ]
        }.filter { !$0.isEmpty }

        let combinedTagString = (
            json.tags.array.map(\.string)
            + relationTitles
            + [
                json.tags.string,
                json.ttitle.string,
                json.targetRow.title.string,
                json.topic_title.string,
                json.message_title.string,
                json.title.string,
                effectiveExtraTitle
            ]
        ).joined(separator: " ")

        let hasExplicitErshouPrice = Self.parseNumericPrice(json.ershou_price) > 0
            || Self.parseNumericPrice(json.ershou_info.product_price) > 0
            || Self.parseNumericPrice(json.ershou_info.parsed.product_price) > 0
            || Self.parseNumericPrice(json.ershouInfo.product_price) > 0
            || Self.parseNumericPrice(json.ershouInfo.parsed.product_price) > 0
        let hasBodyTradePhrase = Self.hasExplicitTradeBodyPhrase(in: plainBody)
        let isSecondHandPost = parsedType == "ershou"
            || parsedType.lowercased().contains("second")
            || Self.containsTradeKeyword(json.feedTypeName.string)
            || Self.containsTradeKeyword(combinedTagString)
            || hasExplicitErshouPrice
            || isFaceDeal
            || !json.ershou_info.isNull
            || !json.ershou_data.isNull
            || !json.second_hand.isNull
            || !json.second_hand_info.isNull
            || !xianyuURL.isEmpty
            || hasBodyTradePhrase

        let isDaoshoujiaPost = resolvedSubTabID == "6"
            || Self.parseNumericPrice(json.final_price) > 0
            || extraObjects.contains { Self.parseNumericPrice($0.final_price) > 0 || Self.parseNumericPrice($0.finalPrice) > 0 }
            || combinedTagString.contains("到手价")
            || json.feedTypeName.string.contains("到手价")
            || json.info.string.contains("到手价")
            || json.infoHtml.string.contains("到手价")
            || extraDescriptiveTexts.contains { $0.contains("到手价") }

        let isPriceRelatedContext = isSecondHandPost
            || isDaoshoujiaPost
            || !effectiveExtraURL.isEmpty
            || !skuConfigName.isEmpty
            || combinedTagString.contains("好价")
            || combinedTagString.contains("价格")
            || plainBody.contains("到手")
            || plainBody.contains("实付")
            || plainBody.contains("入手价")
            || plainBody.contains("购入价")
            || plainBody.contains("成交价")

        if isFaceDeal && parsedPriceNum <= 0 && rawPriceString.isEmpty {
            priceText = "价格面议"
        } else if parsedPriceNum > 0 {
            let formatted = parsedPriceNum.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(parsedPriceNum))
                : String(format: "%.2f", parsedPriceNum)
            priceText = "¥\(formatted)"
        } else if !rawPriceString.isEmpty {
            priceText = Self.formatRawPrice(rawPriceString)
        } else {
            let combinedPriceSearchText = ([
                json.message_title.string,
                json.title.string,
                json.sub_title.string,
                json.description.string,
                effectiveExtraTitle,
                resolvedExtraInfo,
                extraInfoFromObj,
                json.info.string,
                FeedHTMLParser.plainText(json.infoHtml.string),
                json.tinfo.string,
                rawSubDataScalar
            ] + extraDescriptiveTexts + [plainBody, articlePartsText])
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            priceText = Self.extractInferredPrice(
                from: combinedPriceSearchText,
                allowLooseUnitMatch: isPriceRelatedContext
            )
        }

        extraLinks = Self.buildExtraLinks(
            primaryTitle: effectiveExtraTitle,
            primaryURL: effectiveExtraURL,
            primaryPic: resolvedExtraPic.isEmpty ? extraPicFromObj : resolvedExtraPic,
            primaryInfo: resolvedExtraInfo.isEmpty ? extraInfoFromObj : resolvedExtraInfo,
            xianyuURL: xianyuURL,
            extraObjects: extraObjects,
            messageHTML: json.message.string,
            isSecondHand: isSecondHandPost
        )

        let rawOrigPrice = ([
            Self.parseNumericPrice(json.orig_price),
            Self.parseNumericPrice(json.origin_price),
            Self.parseNumericPrice(json.ershou_origin_price),
            Self.parseNumericPrice(json.old_price)
        ] + extraObjects.flatMap { obj in
            [
                Self.parseNumericPrice(obj.orig_price),
                Self.parseNumericPrice(obj.origin_price),
                Self.parseNumericPrice(obj.ershou_origin_price),
                Self.parseNumericPrice(obj.old_price)
            ]
        }).first { $0 > 0 } ?? 0
        if rawOrigPrice > 0 {
            let formatted = rawOrigPrice.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(rawOrigPrice))
                : String(format: "%.2f", rawOrigPrice)
            originalPriceText = "¥\(formatted)"
        } else {
            let rawOrigStr = ([json.orig_price.string, json.origin_price.string]
                + extraObjects.flatMap { [$0.orig_price.string, $0.origin_price.string] })
                .first { !$0.isEmpty && $0 != "0" } ?? ""
            originalPriceText = rawOrigStr.isEmpty ? "" : Self.formatRawPrice(rawOrigStr)
        }

        let provinceText = ([json.ershou_province.string, json.province.string]
            + extraObjects.map(\.province.string))
            .first { !$0.isEmpty } ?? ""
        let rawCity = ([
            json.ershou_city.string,
            json.city.string,
            json.long_location.string
        ] + extraObjects.flatMap { [$0.city.string, $0.area.string, $0.location.string] })
            .first { !$0.isEmpty } ?? ""
        if !provinceText.isEmpty && !rawCity.isEmpty && !rawCity.contains(provinceText) {
            cityText = "\(provinceText) \(rawCity)"
        } else {
            cityText = !rawCity.isEmpty ? rawCity : provinceText
        }

        let explicitDealText = ([
            json.ershou_status_text.string,
            json.deal_status_text.string
        ] + extraObjects.flatMap { obj in
            [
                obj.ershou_status_text.string,
                obj.deal_status_text.string,
                obj.status_text.string,
                obj.status_desc.string,
                obj.product_status.string
            ]
        }).first { !$0.isEmpty } ?? ""

        let statusNodes: [JSON] = [
            json.ershou_status,
            json.deal_status,
            json.trade_status,
            json.sell_status
        ] + extraObjects.flatMap { obj in
            [obj.ershou_status, obj.deal_status, obj.trade_status, obj.sell_status, obj.status]
        }
        let hasCompletedStatusNode = statusNodes.contains { node in
            guard node.exists else { return false }
            let lower = node.string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower.contains("完成") || lower.contains("已售") || lower.contains("已出") || lower.contains("已交易")
                || lower == "sold" || lower == "complete" || lower == "completed" || lower == "finished" || lower == "done" {
                return true
            }
            if let num = Int(lower) {
                return num < 0 || num >= 2
            }
            if node.isObject == false && node.string.isEmpty {
                return node.int < 0 || node.int >= 2
            }
            return false
        }
        let hasCompletedFlag = ([
            json.is_complete,
            json.is_completed,
            json.is_sold,
            json.complete_time,
            json.deal_time
        ] + extraObjects.flatMap { obj in
            [obj.is_complete, obj.is_completed, obj.is_sold, obj.is_deal, obj.complete_time, obj.deal_time, obj.sold_time]
        }).contains { $0.bool || $0.int > 0 }
        let completedKeywordHit = [
            explicitDealText,
            resolvedExtraInfo,
            extraInfoFromObj,
            effectiveExtraTitle,
            json.feedTypeName.string,
            json.info.string,
            json.infoHtml.string
        ].contains { text in
            text.contains("交易完成") || text.contains("已交易") || text.contains("已售出")
        }

        if !explicitDealText.isEmpty {
            dealStatusText = explicitDealText
        } else if hasCompletedStatusNode || hasCompletedFlag || completedKeywordHit {
            dealStatusText = "交易完成"
        } else if !isSecondHandPost && isDaoshoujiaPost {
            if !skuConfigName.isEmpty {
                dealStatusText = skuConfigName.contains("到手价") ? skuConfigName : "到手价 · \(skuConfigName)"
            } else {
                dealStatusText = "到手价"
            }
        } else if !skuConfigName.isEmpty {
            dealStatusText = skuConfigName
        } else {
            dealStatusText = ([resolvedExtraInfo, extraInfoFromObj]).first {
                !$0.isEmpty && $0 != "闲鱼" && $0 != "转转"
            } ?? ""
        }

        subTabBadgeText = Self.buildSubTabBadgeText(
            subTabID: resolvedSubTabID,
            rawSubDataScalar: rawSubDataScalar,
            extraObjects: extraObjects
        )

        readNum = [
            json.readNum.int,
            json.read_num.int,
            json.viewnum.int,
            json.view_num.int,
            json.hitnum.int,
            json.hit_num.int,
            json.extraDataArr.readNum.int,
            json.extraData.parsed.readNum.int
        ].first { $0 > 0 } ?? 0

        isSelfOnly = json.publishStatus.int == 1
            || json.publish_status.int == 1
            || json.publishStatus.string == "1"
            || json.publish_status.string == "1"

        isModified = json.is_modified.int > 0
            || json.isModified.int > 0
            || json.is_modified.bool
            || json.isModified.bool
            || json.change_count.int > 0
            || json.changeCount.int > 0

        var resolvedTargetTitle = ""
        var resolvedTargetURL = ""
        var resolvedTargetPic = ""
        var resolvedTargetInfo = ""
        if json.targetRow.exists, !json.targetRow.isNull {
            resolvedTargetTitle = json.targetRow.title.string
            resolvedTargetURL = json.targetRow.url.string
            resolvedTargetPic = coolapkNormalizedURL(json.targetRow.logo.string.isEmpty ? json.targetRow.pic.string : json.targetRow.logo.string)
            resolvedTargetInfo = json.targetRow.description.string
        }
        if resolvedTargetTitle.isEmpty, !json.ttitle.string.isEmpty {
            resolvedTargetTitle = json.ttitle.string
            resolvedTargetURL = json.turl.string
            resolvedTargetPic = coolapkNormalizedURL(json.tpic.string)
        }
        if resolvedTargetTitle.isEmpty, !json.topic_title.string.isEmpty {
            resolvedTargetTitle = json.topic_title.string
        }
        targetTitle = resolvedTargetTitle
        targetURL = resolvedTargetURL
        targetPic = resolvedTargetPic
        targetInfo = resolvedTargetInfo

        let parsedRatingInfo = FeedRatingInfo.from(
            json: json,
            targetTitle: resolvedTargetTitle,
            targetLogo: resolvedTargetPic,
            targetURL: resolvedTargetURL
        )
        ratingInfo = parsedRatingInfo
        videoInfo = FeedVideoInfo.from(json: json, extraObjects: extraObjects)

        switch feedType {
        case "feedArticle": kind = .feedArticle
        case "product": kind = .product
        case "topic": kind = .topic
        case "question": kind = .question
        case "answer": kind = .answer
        case "vote": kind = .vote
        case "dyh", "dyhArticle": kind = .dyh
        case "ershou": kind = .ershou
        case "rating", "ratingFeed", "feed_rating", "nodeRating": kind = .rating
        case "feed": kind = isArticle ? .feedArticle : (parsedRatingInfo != nil ? .rating : (isSecondHandPost ? .ershou : .feed))
        default: kind = !questionID.isEmpty ? .answer : (parsedRatingInfo != nil ? .rating : (isSecondHandPost ? .ershou : (parsedType.isEmpty ? .feed : .unknown)))
        }

        let sourceObj = (json.sourceFeed.exists && !json.sourceFeed.isNull && json.sourceFeed.isObject)
            ? json.sourceFeed
            : ((json.forwardSourceFeed.exists && !json.forwardSourceFeed.isNull && json.forwardSourceFeed.isObject) ? json.forwardSourceFeed : .null)
        if sourceObj.exists, !sourceObj.isNull {
            forwardSourceName = sourceObj.username.string
            sourceFeed = ForwardedContent(json: sourceObj)
        } else {
            forwardSourceName = ""
            sourceFeed = nil
        }
        if !json.forwardSourceName.string.isEmpty {
            forwardSourceName = json.forwardSourceName.string
        }

        let directReplies = json.replyRows.array.map { ReplyItem(json: $0) }
        if !directReplies.isEmpty {
            replyRows = directReplies
        } else {
            let hotRaw = !json.hotReplyRows.array.isEmpty ? json.hotReplyRows.array : json.hot_reply_rows.array
            replyRows = hotRaw.map { ReplyItem(json: $0) }
        }
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
        if !resolvedTargetTitle.isEmpty, !tags.contains(resolvedTargetTitle) {
            tags.append(resolvedTargetTitle)
        }
        topicTags = tags

        let allRelationRowArrays = json.relationRows.array
            + json.relation_rows.array
            + json.extraRows.array
            + json.extra_rows.array
            + json.productRows.array
            + json.product_rows.array

        var tIDs: [String] = []
        if !json.tid.identifier.isEmpty { tIDs.append(json.tid.identifier) }
        for rel in allRelationRowArrays {
            let rid = rel.entityId.identifier.isEmpty ? rel.id.identifier : rel.entityId.identifier
            if !rid.isEmpty { tIDs.append(rid) }
        }
        topicIDs = tIDs

        var builtRelations: [FeedRelationEntity] = []
        var seenRelationKeys = Set<String>()
        func appendRelation(id: String, title: String, url: String, pic: String, entityType: String) {
            let cleanTitle = TopicItem.cleanTitle(title)
            let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty || !cleanURL.isEmpty else { return }
            if cleanURL.hasPrefix("http://") || cleanURL.hasPrefix("https://") {
                if !cleanURL.contains("coolapk.com") { return }
            }
            let dedupeKey = cleanTitle.isEmpty ? cleanURL.lowercased() : cleanTitle.lowercased()
            guard seenRelationKeys.insert(dedupeKey).inserted else { return }
            let resolvedURL = cleanURL.isEmpty ? "/t/\(cleanTitle)" : cleanURL
            let entityID = id.isEmpty ? "rel-\(builtRelations.count)-\(dedupeKey)" : id
            builtRelations.append(FeedRelationEntity(
                id: entityID,
                title: cleanTitle.isEmpty ? resolvedURL : cleanTitle,
                url: resolvedURL,
                pic: coolapkNormalizedURL(pic),
                entityType: entityType
            ))
        }

        if !resolvedTargetTitle.isEmpty || !resolvedTargetURL.isEmpty {
            appendRelation(
                id: json.targetRow.id.identifier.isEmpty ? json.tid.identifier : json.targetRow.id.identifier,
                title: resolvedTargetTitle,
                url: resolvedTargetURL,
                pic: resolvedTargetPic,
                entityType: json.targetRow.targetType.string.isEmpty ? json.targetRow.entityType.string : json.targetRow.targetType.string
            )
        }
        for rel in allRelationRowArrays {
            let relPic = rel.logo.string.isEmpty ? rel.pic.string : rel.logo.string
            let relID = rel.id.identifier.isEmpty ? rel.entityId.identifier : rel.id.identifier
            appendRelation(
                id: relID,
                title: rel.title.string,
                url: rel.url.string,
                pic: relPic,
                entityType: rel.entityType.string.isEmpty ? rel.targetType.string : rel.entityType.string
            )
        }
        for tag in tags {
            appendRelation(id: "", title: tag, url: "/t/\(tag)", pic: "", entityType: "topic")
        }
        relationEntities = builtRelations
    }

    public var forwardLabel: String {
        sourceFeed != nil ? "转发动态" : ""
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try c.decode(String.self, forKey: .id)
        id = decodedID
        let decodedTarget = try c.decodeIfPresent(String.self, forKey: .targetFeedID) ?? ""
        targetFeedID = (decodedTarget.isEmpty || decodedTarget == "0") ? decodedID : decodedTarget
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .feed
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        messageTitle = try c.decodeIfPresent(String.self, forKey: .messageTitle) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        deviceTitle = try c.decodeIfPresent(String.self, forKey: .deviceTitle) ?? ""
        ipLocation = try c.decodeIfPresent(String.self, forKey: .ipLocation) ?? ""
        dateline = try c.decodeIfPresent(Date.self, forKey: .dateline)
        datelineText = try c.decodeIfPresent(String.self, forKey: .datelineText) ?? ""
        authorLoginTime = try c.decodeIfPresent(Date.self, forKey: .authorLoginTime)
        isAuthorFollowed = try c.decodeIfPresent(Bool.self, forKey: .isAuthorFollowed) ?? false
        likeNum = try c.decodeIfPresent(Int.self, forKey: .likeNum) ?? 0
        commentNum = try c.decodeIfPresent(Int.self, forKey: .commentNum) ?? 0
        replyNum = try c.decodeIfPresent(Int.self, forKey: .replyNum) ?? 0
        forwardNum = try c.decodeIfPresent(Int.self, forKey: .forwardNum) ?? 0
        favNum = try c.decodeIfPresent(Int.self, forKey: .favNum) ?? 0
        shareNum = try c.decodeIfPresent(Int.self, forKey: .shareNum) ?? 0
        pics = try c.decodeIfPresent([String].self, forKey: .pics) ?? []
        mediaItems = try c.decodeIfPresent([FeedMedia].self, forKey: .mediaItems) ?? []
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
        isLiked = try c.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false
        isFavorited = try c.decodeIfPresent(Bool.self, forKey: .isFavorited) ?? false
        isHeadline = try c.decodeIfPresent(Bool.self, forKey: .isHeadline) ?? false
        infoText = try c.decodeIfPresent(String.self, forKey: .infoText) ?? ""
        feedTypeName = try c.decodeIfPresent(String.self, forKey: .feedTypeName) ?? "动态"
        feedType = try c.decodeIfPresent(String.self, forKey: .feedType) ?? "feed"
        targetTitle = try c.decodeIfPresent(String.self, forKey: .targetTitle) ?? ""
        targetURL = try c.decodeIfPresent(String.self, forKey: .targetURL) ?? ""
        targetPic = try c.decodeIfPresent(String.self, forKey: .targetPic) ?? ""
        targetInfo = try c.decodeIfPresent(String.self, forKey: .targetInfo) ?? ""
        extraTitle = try c.decodeIfPresent(String.self, forKey: .extraTitle) ?? ""
        extraURL = try c.decodeIfPresent(String.self, forKey: .extraURL) ?? ""
        extraPic = try c.decodeIfPresent(String.self, forKey: .extraPic) ?? ""
        extraInfo = try c.decodeIfPresent(String.self, forKey: .extraInfo) ?? ""
        priceText = try c.decodeIfPresent(String.self, forKey: .priceText) ?? ""
        originalPriceText = try c.decodeIfPresent(String.self, forKey: .originalPriceText) ?? ""
        cityText = try c.decodeIfPresent(String.self, forKey: .cityText) ?? ""
        dealStatusText = try c.decodeIfPresent(String.self, forKey: .dealStatusText) ?? ""
        xianyuURL = try c.decodeIfPresent(String.self, forKey: .xianyuURL) ?? ""
        extraLinks = try c.decodeIfPresent([FeedExtraLink].self, forKey: .extraLinks) ?? []
        forwardSourceName = try c.decodeIfPresent(String.self, forKey: .forwardSourceName) ?? ""
        replyRows = try c.decodeIfPresent([ReplyItem].self, forKey: .replyRows) ?? []
        topReplyRows = try c.decodeIfPresent([ReplyItem].self, forKey: .topReplyRows) ?? []
        sourceFeed = try c.decodeIfPresent(ForwardedContent.self, forKey: .sourceFeed)
        rankScore = try c.decodeIfPresent(Int.self, forKey: .rankScore) ?? 0
        articleParts = try c.decodeIfPresent([FeedArticlePart].self, forKey: .articleParts) ?? []
        vote = try c.decodeIfPresent(VoteInfo.self, forKey: .vote)
        questionID = try c.decodeIfPresent(String.self, forKey: .questionID) ?? ""
        questionTitle = try c.decodeIfPresent(String.self, forKey: .questionTitle) ?? ""
        questionAnswerNum = try c.decodeIfPresent(Int.self, forKey: .questionAnswerNum) ?? 0
        topicTags = try c.decodeIfPresent([String].self, forKey: .topicTags) ?? []
        topicIDs = try c.decodeIfPresent([String].self, forKey: .topicIDs) ?? []
        if let decodedRelations = try c.decodeIfPresent([FeedRelationEntity].self, forKey: .relationEntities) {
            relationEntities = decodedRelations
        } else if !targetTitle.isEmpty || !targetURL.isEmpty {
            relationEntities = [FeedRelationEntity(
                id: "target-\(targetTitle)",
                title: targetTitle.isEmpty ? targetURL : targetTitle,
                url: targetURL.isEmpty ? "/t/\(targetTitle)" : targetURL,
                pic: targetPic
            )]
        } else {
            relationEntities = []
        }
        changeCount = try c.decodeIfPresent(Int.self, forKey: .changeCount) ?? 0
        totalPicCount = try c.decodeIfPresent(Int.self, forKey: .totalPicCount) ?? mediaItems.count
        isTruncated = try c.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
        subTabID = try c.decodeIfPresent(String.self, forKey: .subTabID) ?? ""
        subTabBadgeText = try c.decodeIfPresent(String.self, forKey: .subTabBadgeText) ?? ""
        readNum = try c.decodeIfPresent(Int.self, forKey: .readNum) ?? 0
        isSelfOnly = try c.decodeIfPresent(Bool.self, forKey: .isSelfOnly) ?? false
        isModified = try c.decodeIfPresent(Bool.self, forKey: .isModified) ?? (changeCount > 0)
        ratingInfo = try c.decodeIfPresent(FeedRatingInfo.self, forKey: .ratingInfo)
        videoInfo = try c.decodeIfPresent(FeedVideoInfo.self, forKey: .videoInfo)
    }

    private static func extractFeedIDFromURL(_ rawURL: String) -> String? {
        guard !rawURL.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"/feed/(\d+)"#),
              let match = regex.firstMatch(in: rawURL, range: NSRange(rawURL.startIndex..<rawURL.endIndex, in: rawURL)),
              let range = Range(match.range(at: 1), in: rawURL) else {
            return nil
        }
        let id = String(rawURL[range])
        return (id.isEmpty || id == "0") ? nil : id
    }

    public static func isXianyuOrTradeURL(_ raw: String) -> Bool {
        let lower = unwrapCoolapkRedirectURL(raw).lowercased()
        return lower.contains("goofish.com")
            || lower.contains("idlefish")
            || lower.contains("xianyu")
            || lower.contains("tb.cn")
            || lower.contains("taobao.com")
            || lower.contains("tmall.com")
            || lower.contains("fleamarket://")
            || lower.contains("tbopen://")
            || lower.contains("zhuanzhuan")
            || lower.contains("zzopen://")
            || lower.contains("58.com")
            || lower.contains("aihuishou.com")
            || lower.contains("paipai.com")
            || lower.contains("dewu.com")
            || lower.contains("poizon.com")
            || lower.contains("95fenapp.com")
            || lower.contains("weidian.com")
            || lower.contains("youzan.com")
            || lower.contains("1688.com")
            || lower.contains("taobao://")
            || lower.contains("jd.com")
            || lower.contains("3.cn")
            || lower.contains("pinduoduo.com")
            || lower.contains("yangkeduo.com")
    }

    public static func isSpecificXianyuURL(_ raw: String) -> Bool {
        let lower = unwrapCoolapkRedirectURL(raw).lowercased()
        return lower.contains("goofish.com")
            || lower.contains("idlefish")
            || lower.contains("xianyu")
            || lower.contains("tb.cn")
            || lower.contains("fleamarket://")
            || lower.contains("tbopen://")
            || lower.contains("2.taobao.com")
    }

    public static func unwrapCoolapkRedirectURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if (trimmed.contains("coolapk.com/link") || trimmed.hasPrefix("/link?")),
           let comps = URLComponents(string: trimmed.hasPrefix("/") ? "https://www.coolapk.com" + trimmed : trimmed),
           let target = comps.queryItems?.first(where: { $0.name == "url" || $0.name == "target" })?.value,
           !target.isEmpty {
            return target
        }
        return trimmed
    }

    private static func formatRawPrice(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains("面议") { return trimmed }
        if trimmed.hasPrefix("¥") || trimmed.hasPrefix("￥") { return trimmed }
        return "¥\(trimmed)"
    }

    public static func parseNumericPrice(_ node: JSON) -> Double {
        if case let .number(num) = node.value {
            return num.isFinite && num > 0 ? num : 0
        }
        return parseNumericPriceString(node.string)
    }

    public static func parseNumericPriceString(_ raw: String) -> Double {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return 0 }
        while cleaned.hasPrefix("¥") || cleaned.hasPrefix("￥") || cleaned.hasPrefix("$") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for suffix in ["元起", "元", "块", "起", "RMB", "rmb"] {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let noCommas = cleaned.replacingOccurrences(of: ",", with: "")
        if let val = Double(noCommas), val.isFinite, val > 0 {
            return val
        }
        return 0
    }

    private static let excludedNestedWalkKeys: Set<String> = [
        "replyrows", "topreplyrows", "hotreplyrows", "hot_reply_rows",
        "userinfo", "user_info", "sourcefeed", "source_feed", "forwardsourcefeed",
        "picarr", "pic_arr", "imageurilist", "image_uri_list", "vote", "useraction", "user_action"
    ]

    private static func collectAllExtraObjects(from json: JSON, articleOutputArray: [JSON]) -> [JSON] {
        var results: [JSON] = []
        let explicitSeeds: [JSON] = [
            json.tsubdata,
            json.tsubdata.parsed,
            json.tsub_data,
            json.tsub_data.parsed,
            json.subData,
            json.subData.parsed,
            json.sub_data,
            json.sub_data.parsed,
            json.target_sub_data,
            json.target_sub_data.parsed,
            json.targetSubData,
            json.targetSubData.parsed,
            json.subTabData,
            json.subTabData.parsed,
            json.sub_tab_data,
            json.sub_tab_data.parsed,
            json.subTabFeedCard,
            json.subTabFeedCard.parsed,
            json.sub_tab_feed_card,
            json.sub_tab_feed_card.parsed,
            json.subTabCard,
            json.subTabCard.parsed,
            json.sub_tab_card,
            json.sub_tab_card.parsed,
            json.sub_tab_info,
            json.sub_tab_info.parsed,
            json.subTabInfo,
            json.subTabInfo.parsed,
            json.product_info,
            json.product_info.parsed,
            json.productInfo,
            json.productInfo.parsed,
            json.product_card,
            json.product_card.parsed,
            json.productCard,
            json.productCard.parsed,
            json.ershou_info,
            json.ershou_info.parsed,
            json.ershouInfo,
            json.ershouInfo.parsed,
            json.ershou_data,
            json.ershou_data.parsed,
            json.ershou,
            json.second_hand,
            json.second_hand_info,
            json.second_hand_info.parsed,
            json.ershou_product,
            json.ershou_product.parsed,
            json.trade_info,
            json.trade_info.parsed,
            json.goods_info,
            json.goods_info.parsed,
            json.media_info,
            json.media_info.parsed,
            json.extraDataArr,
            json.extraDataArr.parsed,
            json.extra_data_arr,
            json.extra_data_arr.parsed,
            json.extraData,
            json.extraData.parsed,
            json.extra_data,
            json.extra_data.parsed,
            json.extra_fromApi,
            json.extra_fromApi.parsed,
            json.extraFromApi,
            json.extraFromApi.parsed,
            json.extra_info.parsed,
            json.extraInfo.parsed
        ]
            + json.extra_entities.array
            + json.extraEntities.array
            + json.extraRows.array
            + json.extra_rows.array
            + json.productRows.array
            + json.product_rows.array
            + json.entities.array
            + articleOutputArray

        func ingestNode(_ node: JSON, depth: Int) {
            guard depth <= 3, !node.isNull else { return }
            if node.isObject {
                results.append(node)
                for (k, v) in node.dictionary {
                    let lowerK = k.lowercased()
                    guard !excludedNestedWalkKeys.contains(lowerK) else { continue }
                    if v.isObject || !v.array.isEmpty {
                        ingestNode(v, depth: depth + 1)
                    } else if case let .string(s) = v.value {
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
                            ingestNode(v.parsed, depth: depth + 1)
                        }
                    }
                }
            } else if !node.array.isEmpty {
                for elem in node.array {
                    ingestNode(elem, depth: depth + 1)
                }
            } else if case let .string(s) = node.value {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
                    ingestNode(node.parsed, depth: depth + 1)
                }
            }
        }

        for seed in explicitSeeds {
            ingestNode(seed, depth: 1)
        }

        for (k, v) in json.dictionary {
            let lowerK = k.lowercased()
            guard !excludedNestedWalkKeys.contains(lowerK), lowerK != "targetrow", lowerK != "target_row", lowerK != "relationrows", lowerK != "relation_rows" else { continue }
            if v.isObject || !v.array.isEmpty {
                ingestNode(v, depth: 1)
            } else if case let .string(s) = v.value {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
                    ingestNode(v.parsed, depth: 1)
                }
            }
        }

        return results
    }

    private static let ignoredDynamicPriceKeys: Set<String> = [
        "orig_price", "origin_price", "ershou_origin_price", "old_price",
        "price_min", "price_max", "pricemin", "pricemax", "price_currency", "pricecurrency"
    ]

    private static func extractDynamicPriceFromExtraObjects(
        json: JSON,
        extraObjects: [JSON],
        subTabID: String,
        rawSubDataScalar: String
    ) -> Double {
        if subTabID == "6", !rawSubDataScalar.isEmpty {
            let directScalar = parseNumericPriceString(rawSubDataScalar)
            if directScalar > 0 { return directScalar }
        }

        for (k, v) in json.dictionary {
            let lowerK = k.lowercased()
            guard !ignoredDynamicPriceKeys.contains(lowerK) else { continue }
            if lowerK.contains("price") || lowerK.contains("daoshou") {
                let val = parseNumericPrice(v)
                if val > 0 { return val }
            }
        }

        for obj in extraObjects {
            let dict = obj.dictionary
            for (k, v) in dict {
                let lowerK = k.lowercased()
                guard !ignoredDynamicPriceKeys.contains(lowerK) else { continue }
                if lowerK.contains("price") || lowerK.contains("daoshou") {
                    let val = parseNumericPrice(v)
                    if val > 0 { return val }
                }
            }

            let objHeader = [
                obj.title.string,
                obj.label.string,
                obj.name.string,
                obj.key.string,
                obj.sub_title.string,
                obj.subTitle.string,
                obj.description.string,
                obj.info.string
            ].joined(separator: " ")

            if subTabID == "6" || objHeader.contains("到手价") || objHeader.contains("实付") || objHeader.contains("入手价") || objHeader.contains("成交价") {
                let valueCandidates: [JSON] = [
                    obj.final_price,
                    obj.finalPrice,
                    obj.price,
                    obj.value,
                    obj.num,
                    obj.amount,
                    obj.money,
                    obj.data,
                    obj.sub_title,
                    obj.subTitle,
                    obj.title,
                    obj.description,
                    obj.text
                ]
                for candidate in valueCandidates {
                    let val = parseNumericPrice(candidate)
                    if val > 0 && val < 1_000_000 {
                        return val
                    }
                }
            }
        }
        return 0
    }

    private static func buildSubTabBadgeText(
        subTabID: String,
        rawSubDataScalar: String,
        extraObjects: [JSON]
    ) -> String {
        switch subTabID {
        case "1":
            if !rawSubDataScalar.isEmpty, let hrs = Double(rawSubDataScalar), hrs > 0 {
                let formatted = hrs.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(hrs)) : String(format: "%.1f", hrs)
                return "亮屏续航 \(formatted) 小时"
            }
            for obj in extraObjects {
                let hrs = [obj.hours.double, obj.battery_hours.double, obj.value.double].first { $0 > 0 } ?? 0
                if hrs > 0 {
                    let formatted = hrs.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(hrs)) : String(format: "%.1f", hrs)
                    return "亮屏续航 \(formatted) 小时"
                }
            }
            return ""
        case "2":
            for obj in extraObjects {
                let antutu = [obj.antutu_score.int, obj.antutuScore.int].first { $0 > 0 } ?? 0
                let single = [obj.geek_bench_single_score.int, obj.geekBenchSingleScore.int].first { $0 > 0 } ?? 0
                let multi = [obj.geek_bench_multi_score.int, obj.geekBenchMultiScore.int].first { $0 > 0 } ?? 0
                let mark3d = [obj.dictionary["3d_mark_score"]?.int ?? 0, obj.threeDMarkScore.int].first { $0 > 0 } ?? 0
                var parts: [String] = []
                if antutu > 0 { parts.append("安兔兔 \(antutu)") }
                if single > 0 { parts.append("GeekBench 单核 \(single)") }
                if multi > 0 { parts.append("多核 \(multi)") }
                if mark3d > 0 { parts.append("3DMark \(mark3d)") }
                if !parts.isEmpty {
                    return parts.joined(separator: " · ")
                }
            }
            return ""
        case "5":
            let severityMap: [String: String] = [
                "1": "较低",
                "2": "一般",
                "3": "次要",
                "4": "严重",
                "5": "致命"
            ]
            if let label = severityMap[rawSubDataScalar] {
                return "反馈等级：\(label)"
            }
            for obj in extraObjects {
                let code = [obj.level.identifier, obj.severity.identifier, obj.value.identifier].first { !$0.isEmpty } ?? ""
                if let label = severityMap[code] {
                    return "反馈等级：\(label)"
                }
            }
            return ""
        default:
            return ""
        }
    }

    private static func extractFirstXianyuURL(in text: String) -> String? {
        let pattern = #"(?:https?://|fleamarket://|tbopen://)[^\s"'<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: nsRange) {
            if let range = Range(match.range, in: text) {
                let candidate = unwrapCoolapkRedirectURL(
                    String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)]}>\"'"))
                )
                if isXianyuOrTradeURL(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    public static func containsTradeKeyword(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.contains("二手")
            || text.contains("闲置")
            || text.contains("交易")
    }

    private static func hasExplicitTradeBodyPhrase(in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let pattern = #"(?:(?<![0-9a-zA-Z.])\d{1,6}(?:\.\d{1,2})?\s*(?:元|块|rmb|RMB)?\s*(?:包邮|包顺丰|到付|自提|不刀|可小刀|明盘))|(?:走闲鱼|闲鱼交易|出闲置)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: nsRange) != nil
    }

    private static func extractInferredPrice(from text: String, allowLooseUnitMatch: Bool = true) -> String {
        guard !text.isEmpty else { return "" }
        let numGroup = #"((?:\d{1,3}(?:,\d{3})+|\d{1,6})(?:\.\d{1,2})?)"#
        let strictPatterns = [
            #"(?:到手价|到手|实付|入手价|购入价|成交价|价格|售价|出价|明盘|一口价|实价|现价|好价|特价)\s*(?:为|是|仅|约)?\s*[：:=]?\s*[¥￥]?\s*"# + numGroup + #"(?![0-9.])"#,
            #"(?<![0-9a-zA-Z.])"# + numGroup + #"\s*(?:元|块|块钱|r|R|rmb|RMB|大洋)?\s*(?:到手价|到手|入手|拿下|实付|购入|成交)"#,
            #"[¥￥]\s*"# + numGroup + #"(?![0-9.])"#,
            #"(?<![0-9a-zA-Z.])"# + numGroup + #"\s*(?:元|块|块钱|r|R|rmb|RMB)?\s*(?:包邮|包顺丰|包普快|到付|自提|不刀|可小刀|明盘)"#,
            #"(?:出|转让|只要)\s*[：:=]?\s*[¥￥]?\s*"# + numGroup + #"\s*(?:元|块|包邮|包顺丰|到付|自提|不刀|r|R)"#
        ]
        let loosePatterns = [
            #"(?<![0-9a-zA-Z./\-])"# + numGroup + #"\s*(?:元|块|块钱|r|R|rmb|RMB)(?![0-9a-zA-Z.])"#,
            #"(?<![0-9a-zA-Z./\-])"# + numGroup + #"\s*出(?![0-9a-zA-Z.])"#
        ]
        let allPatterns = allowLooseUnitMatch ? (strictPatterns + loosePatterns) : strictPatterns
        for pattern in allPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let num = String(text[range]).replacingOccurrences(of: ",", with: "")
                if let val = Double(num), val > 0 {
                    return "¥\(num)"
                }
            }
        }
        return ""
    }

    private static func shouldDisplayExtractedLink(_ rawURL: String, anchorTitle: String = "") -> Bool {
        let trimmed = unwrapCoolapkRedirectURL(rawURL).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        let cleanAnchor = anchorTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAnchor == "查看更多" || cleanAnchor == "全文" || cleanAnchor.hasPrefix("#") || cleanAnchor.hasPrefix("@") {
            return false
        }
        if lower.hasPrefix("/u/") || lower.hasPrefix("/t/") || lower.hasPrefix("/topic/")
            || lower.hasPrefix("/product/") || lower.hasPrefix("/dyh/")
            || lower.hasPrefix("/apk/") || lower.hasPrefix("/game/") || lower.hasPrefix("/collection/")
            || lower.hasPrefix("coolmarket://") {
            return false
        }
        if lower.hasPrefix("/feed/") && (cleanAnchor.isEmpty || cleanAnchor == "查看更多" || cleanAnchor == "全文") {
            return false
        }
        if lower.contains("image.coolapk.com") || lower.contains("avatar.coolapk.com") {
            return false
        }
        if let url = URL(string: trimmed), let host = url.host?.lowercased(),
           host == "www.coolapk.com" || host == "coolapk.com" || host == "m.coolapk.com" {
            let path = url.path.lowercased()
            if path.hasPrefix("/u/") || path.hasPrefix("/t/") || path.hasPrefix("/topic/") {
                return false
            }
            if path.hasPrefix("/feed/") && (cleanAnchor == "查看更多" || cleanAnchor == "全文") {
                return false
            }
        }
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("fleamarket://")
            || lower.hasPrefix("tbopen://")
            || lower.hasPrefix("zzopen://")
            || lower.hasPrefix("bilibili://")
            || lower.hasPrefix("orpheus://")
    }

    private static func normalizedLinkDedupeKey(_ rawURL: String) -> String {
        var key = unwrapCoolapkRedirectURL(rawURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }

    private static func buildExtraLinks(
        primaryTitle: String,
        primaryURL: String,
        primaryPic: String,
        primaryInfo: String,
        xianyuURL: String,
        extraObjects: [JSON],
        messageHTML: String,
        isSecondHand: Bool
    ) -> [FeedExtraLink] {
        var results: [FeedExtraLink] = []
        var seenKeys = Set<String>()

        func appendCandidate(url raw: String, title: String, pic: String = "", info: String = "") {
            let unwrapped = unwrapCoolapkRedirectURL(raw)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.,;)]}>\"'"))
            guard shouldDisplayExtractedLink(unwrapped, anchorTitle: title) else { return }
            let key = normalizedLinkDedupeKey(unwrapped)
            guard !key.isEmpty, seenKeys.insert(key).inserted else { return }

            let isTrade = isSecondHand || isXianyuOrTradeURL(unwrapped)
            let isSpecificXianyu = isSpecificXianyuURL(unwrapped)
            let platformLabel: String = {
                if isSpecificXianyu { return "闲鱼" }
                let trimmedInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedInfo.isEmpty, trimmedInfo.count <= 12, !trimmedInfo.contains("完成") {
                    return trimmedInfo
                }
                let lower = unwrapped.lowercased()
                if lower.contains("zhuanzhuan") || lower.contains("zzopen://") { return "转转" }
                if lower.contains("jd.com") || lower.contains("3.cn") { return "京东" }
                if lower.contains("taobao.com") || lower.contains("tmall.com") { return "淘宝" }
                if lower.contains("pinduoduo.com") || lower.contains("yangkeduo.com") { return "拼多多" }
                if lower.contains("bilibili.com") || lower.contains("b23.tv") { return "哔哩哔哩" }
                return "平台"
            }()

            let cleanedTitle = FeedHTMLParser.plainText(title).trimmingCharacters(in: .whitespacesAndNewlines)
            let finalTitle: String = {
                if !cleanedTitle.isEmpty, cleanedTitle != "查看链接", cleanedTitle != "网页链接" {
                    return cleanedTitle
                }
                if !primaryTitle.isEmpty, results.isEmpty {
                    return primaryTitle
                }
                if isTrade {
                    return "前往\(platformLabel)查看详情"
                }
                return unwrapped
            }()

            let finalSubtitle: String = {
                if isTrade {
                    return "点击跳转\(platformLabel) · \(unwrapped)"
                }
                let trimmedInfo = info.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedInfo.isEmpty && trimmedInfo != finalTitle {
                    return "\(trimmedInfo) · \(unwrapped)"
                }
                return unwrapped
            }()

            results.append(FeedExtraLink(
                id: "link-\(results.count)-\(key)",
                title: finalTitle,
                url: unwrapped,
                pic: coolapkNormalizedURL(pic),
                subtitle: finalSubtitle,
                isTradeLink: isTrade
            ))
        }

        if !xianyuURL.isEmpty {
            appendCandidate(url: xianyuURL, title: primaryTitle, pic: primaryPic, info: primaryInfo)
        }
        if !primaryURL.isEmpty {
            appendCandidate(url: primaryURL, title: primaryTitle, pic: primaryPic, info: primaryInfo)
        }

        for obj in extraObjects {
            let candidateURL = [
                obj.link_url.string,
                obj.linkUrl.string,
                obj.xianyu_url.string,
                obj.goofish_url.string,
                obj.ershou_url.string,
                obj.trade_url.string,
                obj.jump_url.string,
                obj.buy_url.string,
                obj.sell_url.string,
                obj.item_url.string,
                obj.extra_url.string,
                obj.url.string,
                obj.link.string,
                obj.target_url.string
            ].first { !$0.isEmpty } ?? ""
            guard !candidateURL.isEmpty else { continue }
            let candidateTitle = [
                obj.product_title.string,
                obj.productTitle.string,
                obj.title.string,
                obj.extra_title.string,
                obj.goods_title.string,
                obj.name.string
            ].first { !$0.isEmpty } ?? ""
            let candidatePic = [
                obj.pic.string,
                obj.extra_pic.string,
                obj.cover.string,
                obj.logo.string
            ].first { !$0.isEmpty } ?? ""
            let candidateInfo = [
                obj.link_source.string,
                obj.linkSource.string,
                obj.platform.string,
                obj.info.string,
                obj.extra_info.string,
                obj.sub_title.string
            ].first { !$0.isEmpty } ?? ""
            appendCandidate(url: candidateURL, title: candidateTitle, pic: candidatePic, info: candidateInfo)
        }

        if !messageHTML.isEmpty {
            let anchorPattern = #"<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
            if let regex = try? NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let nsRange = NSRange(messageHTML.startIndex..<messageHTML.endIndex, in: messageHTML)
                for match in regex.matches(in: messageHTML, range: nsRange) {
                    guard let hrefRange = Range(match.range(at: 1), in: messageHTML) else { continue }
                    let rawHref = String(messageHTML[hrefRange])
                        .replacingOccurrences(of: "&amp;", with: "&")
                    let anchorText: String = {
                        guard let textRange = Range(match.range(at: 2), in: messageHTML) else { return "" }
                        return FeedHTMLParser.plainText(String(messageHTML[textRange]))
                    }()
                    appendCandidate(url: rawHref, title: anchorText)
                }
            }

            let plainText = FeedHTMLParser.plainText(messageHTML)
            let urlPattern = #"(?:https?://|fleamarket://|tbopen://|zzopen://)[^\s"'<>\[\]()，。；！？、]+"#
            if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
                let nsRange = NSRange(plainText.startIndex..<plainText.endIndex, in: plainText)
                for match in regex.matches(in: plainText, range: nsRange) {
                    if let range = Range(match.range, in: plainText) {
                        let rawURL = String(plainText[range])
                        appendCandidate(url: rawURL, title: "")
                    }
                }
            }
        }

        return results
    }
}
