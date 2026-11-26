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

public struct FeedItem: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case feed
        case feedArticle
        case product
        case topic
        case question
        case vote
        case dyh
        case ershou
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
    public var relationEntities: [FeedRelationEntity]
    public var changeCount: Int
    public var totalPicCount: Int
    public var isTruncated: Bool

    public var effectiveFeedID: String {
        let candidate = (targetFeedID.isEmpty || targetFeedID == "0") ? id : targetFeedID
        return candidate == "0" ? "" : candidate
    }

    public var needsDetailRefresh: Bool {
        if kind == .feedArticle && articleParts.isEmpty { return true }
        if kind == .vote && vote == nil { return true }
        if isTruncated || message.contains("查看更多") { return true }
        if totalPicCount > mediaItems.count { return true }
        return false
    }

    public var isSecondHand: Bool {
        kind == .ershou
            || feedType == "ershou"
            || feedTypeName.contains("二手")
            || feedTypeName.contains("闲置")
            || !priceText.isEmpty
            || !xianyuURL.isEmpty
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
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON) {
        let rawResolvedID = json.id.exists ? json.id.identifier : json.entityId.identifier
        let nonZeroResolvedID = rawResolvedID == "0" ? "" : rawResolvedID
        let rawEntityType = json.entityType.string.lowercased()
        let explicitFeedID = [json.feed_id.identifier, json.feedId.identifier]
            .first { !$0.isEmpty && $0 != "0" }
            ?? (!rawEntityType.isEmpty && rawEntityType != "feed"
                ? [json.fid.identifier].first { !$0.isEmpty && $0 != "0" }
                : nil)
            ?? Self.extractFeedIDFromURL(json.url.string)
            ?? ""
        let resolvedID = !nonZeroResolvedID.isEmpty ? nonZeroResolvedID : explicitFeedID
        id = resolvedID
        targetFeedID = (!explicitFeedID.isEmpty && !rawEntityType.isEmpty && rawEntityType != "feed")
            ? explicitFeedID
            : resolvedID
        uid = json.uid.identifier
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

        let rawContainers: [JSON] = [
            json.ershou_info,
            json.ershou_info.parsed,
            json.ershou_data,
            json.ershou_data.parsed,
            json.ershou,
            json.second_hand,
            json.goods_info,
            json.goods_info.parsed,
            json.media_info,
            json.extraData,
            json.extraData.parsed,
            json.extra_data,
            json.extra_data.parsed,
            json.extra_info.parsed
        ]
        let extraObjects = rawContainers.filter { $0.isObject }
        let extraTitleFromObj = extraObjects.compactMap { obj in
            [obj.title.string, obj.extra_title.string, obj.goods_title.string, obj.name.string].first { !$0.isEmpty }
        }.first ?? ""
        let extraURLFromObj = extraObjects.compactMap { obj in
            [obj.xianyu_url.string, obj.goofish_url.string, obj.ershou_url.string, obj.extra_url.string, obj.url.string, obj.link.string, obj.target_url.string]
                .first { !$0.isEmpty }
        }.first.map(Self.unwrapCoolapkRedirectURL) ?? ""
        let extraPicFromObj = extraObjects.compactMap { obj in
            [obj.pic.string, obj.extra_pic.string, obj.cover.string, obj.logo.string].first { !$0.isEmpty }
        }.first.map(coolapkNormalizedURL) ?? ""
        let extraInfoFromObj = extraObjects.compactMap { obj in
            [obj.info.string, obj.extra_info.string, obj.sub_title.string, obj.status_text.string].first { !$0.isEmpty }
        }.first ?? ""

        let effectiveExtraTitle = resolvedExtraTitle.isEmpty ? extraTitleFromObj : resolvedExtraTitle
        let effectiveExtraURL = resolvedExtraURL.isEmpty ? extraURLFromObj : resolvedExtraURL
        extraTitle = effectiveExtraTitle
        extraURL = effectiveExtraURL
        extraPic = resolvedExtraPic.isEmpty ? extraPicFromObj : resolvedExtraPic
        extraInfo = resolvedExtraInfo.isEmpty ? extraInfoFromObj : resolvedExtraInfo

        let parsedPriceNum = ([
            json.ershou_price.double,
            json.price.double,
            json.sell_price.double,
            json.goods_price.double,
            json.deal_price.double,
            json.trade_price.double
        ] + extraObjects.flatMap { obj in
            [obj.ershou_price.double, obj.price.double, obj.sell_price.double, obj.goods_price.double, obj.deal_price.double]
        }).first { $0 > 0 } ?? 0

        let rawPriceString = ([
            json.ershou_price.string,
            json.price.string,
            json.price_text.string,
            json.price_str.string,
            json.sell_price.string
        ] + extraObjects.flatMap { obj in
            [obj.ershou_price.string, obj.price.string, obj.price_text.string, obj.price_str.string]
        }).first { !$0.isEmpty && $0 != "0" && $0 != "0.0" } ?? ""

        let relationURLs = json.relationRows.array.map(\.url.string).filter { !$0.isEmpty }
        let linkCandidates = ([
            json.xianyu_url.string,
            json.goofish_url.string,
            json.ershou_url.string,
            json.trade_url.string,
            effectiveExtraURL,
            json.media_url.string,
            json.target_url.string
        ] + extraObjects.flatMap { obj in
            [obj.xianyu_url.string, obj.goofish_url.string, obj.ershou_url.string, obj.trade_url.string, obj.url.string, obj.link.string]
        } + relationURLs)
        .map(Self.unwrapCoolapkRedirectURL)
        .filter { !$0.isEmpty }

        let matchedCandidate = linkCandidates.first { Self.isXianyuOrTradeURL($0) }
        if let matchedCandidate {
            xianyuURL = matchedCandidate
        } else {
            let plainMsg = FeedHTMLParser.plainText(json.message.string)
            xianyuURL = Self.extractFirstXianyuURL(in: json.message.string + " " + plainMsg + " " + effectiveExtraURL + " " + resolvedExtraInfo) ?? ""
        }

        let combinedTagString = (json.tags.array.map(\.string) + [json.tags.string, json.ttitle.string, json.targetRow.title.string])
            .joined(separator: " ")
        let isSecondHandPost = parsedType == "ershou"
            || parsedType.lowercased().contains("second")
            || json.feedTypeName.string.contains("二手")
            || json.feedTypeName.string.contains("闲置")
            || combinedTagString.contains("二手")
            || combinedTagString.contains("闲置")
            || parsedPriceNum > 0
            || !rawPriceString.isEmpty
            || !json.ershou_info.isNull
            || !json.ershou_data.isNull
            || !xianyuURL.isEmpty

        if parsedPriceNum > 0 {
            let formatted = parsedPriceNum.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(parsedPriceNum))
                : String(format: "%.2f", parsedPriceNum)
            priceText = "¥\(formatted)"
        } else if !rawPriceString.isEmpty {
            priceText = Self.formatRawPrice(rawPriceString)
        } else if isSecondHandPost || !effectiveExtraURL.isEmpty {
            let plainBody = FeedHTMLParser.plainText(json.message.string)
            priceText = Self.extractInferredPrice(from: [
                json.message_title.string,
                effectiveExtraTitle,
                resolvedExtraInfo,
                extraInfoFromObj,
                json.info.string,
                plainBody
            ].joined(separator: " "))
        } else {
            priceText = ""
        }

        let rawOrigPrice = ([
            json.orig_price.double,
            json.origin_price.double,
            json.ershou_origin_price.double,
            json.old_price.double
        ] + extraObjects.flatMap { obj in
            [obj.orig_price.double, obj.origin_price.double, obj.ershou_origin_price.double, obj.old_price.double]
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

        cityText = ([
            json.ershou_city.string,
            json.city.string,
            json.long_location.string
        ] + extraObjects.flatMap { [$0.city.string, $0.area.string, $0.location.string] })
            .first { !$0.isEmpty } ?? ""
        dealStatusText = ([
            json.ershou_status_text.string,
            json.deal_status_text.string,
            resolvedExtraInfo,
            extraInfoFromObj
        ]).first { !$0.isEmpty } ?? ""

        switch feedType {
        case "feedArticle": kind = .feedArticle
        case "product": kind = .product
        case "topic": kind = .topic
        case "question": kind = .question
        case "vote": kind = .vote
        case "dyh", "dyhArticle": kind = .dyh
        case "ershou": kind = .ershou
        case "feed": kind = isArticle ? .feedArticle : (isSecondHandPost ? .ershou : .feed)
        default: kind = isSecondHandPost ? .ershou : (parsedType.isEmpty ? .feed : .unknown)
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
            let rid = rel.entityId.identifier.isEmpty ? rel.id.identifier : rel.entityId.identifier
            if !rid.isEmpty { tIDs.append(rid) }
        }
        topicIDs = tIDs

        var builtRelations: [FeedRelationEntity] = []
        var seenRelationKeys = Set<String>()
        func appendRelation(id: String, title: String, url: String, pic: String, entityType: String) {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty || !cleanURL.isEmpty else { return }
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

        if !targetTitle.isEmpty || !targetURL.isEmpty {
            appendRelation(
                id: json.targetRow.id.identifier.isEmpty ? json.tid.identifier : json.targetRow.id.identifier,
                title: targetTitle,
                url: targetURL,
                pic: targetPic,
                entityType: json.targetRow.targetType.string.isEmpty ? json.targetRow.entityType.string : json.targetRow.targetType.string
            )
        }
        for rel in json.relationRows.array {
            let relPic = rel.logo.string.isEmpty ? rel.pic.string : rel.logo.string
            let relID = rel.id.identifier.isEmpty ? rel.entityId.identifier : rel.id.identifier
            appendRelation(
                id: relID,
                title: rel.title.string,
                url: rel.url.string,
                pic: relPic,
                entityType: rel.entityType.string
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
        forwardSourceName = try c.decodeIfPresent(String.self, forKey: .forwardSourceName) ?? ""
        replyRows = try c.decodeIfPresent([ReplyItem].self, forKey: .replyRows) ?? []
        topReplyRows = try c.decodeIfPresent([ReplyItem].self, forKey: .topReplyRows) ?? []
        sourceFeed = try c.decodeIfPresent(ForwardedContent.self, forKey: .sourceFeed)
        rankScore = try c.decodeIfPresent(Int.self, forKey: .rankScore) ?? 0
        articleParts = try c.decodeIfPresent([FeedArticlePart].self, forKey: .articleParts) ?? []
        vote = try c.decodeIfPresent(VoteInfo.self, forKey: .vote)
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
            || lower.contains("zhuanzhuan.com")
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
        if trimmed.hasPrefix("¥") || trimmed.hasPrefix("￥") { return trimmed }
        return "¥\(trimmed)"
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

    private static func extractInferredPrice(from text: String) -> String {
        let patterns = [
            #"[¥￥]\s*(\d+(?:\.\d{1,2})?)"#,
            #"(?:价格|售价|出价|明盘|一口价|实价|现价)\s*[：:=]?\s*(\d+(?:\.\d{1,2})?)"#,
            #"(\d{1,6}(?:\.\d{1,2})?)\s*(?:元|块|出|包邮|自提|不刀|r|R)(?:\b|[^\w])"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: nsRange),
               let range = Range(match.range(at: 1), in: text) {
                let num = String(text[range])
                if !num.isEmpty { return "¥\(num)" }
            }
        }
        return ""
    }
}
