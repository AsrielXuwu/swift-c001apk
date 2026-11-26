import Foundation

public struct UserProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var avatar: String
    public var cover: String
    public var bio: String
    public var level: Int
    public var experience: Int
    public var nextLevelExperience: Int
    public var followNum: Int
    public var fansNum: Int
    public var feedNum: Int
    public var likeNum: Int
    public var verifyLabel: String
    public var verifyTitle: String
    public var location: String
    public var isFollowed: Bool
    public var gender: Int
    public var registerDate: Date?
    public var loginTime: Date?
    public var deviceTitle: String

    public static func == (lhs: UserProfile, rhs: UserProfile) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public init(json: JSON) {
        id = json.uid.exists ? json.uid.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.userBigAvatar.string : json.userAvatar.string
        cover = json.cover.string
        bio = json.bio.string.isEmpty ? json.signature.string : json.bio.string
        level = json.level.int
        experience = json.experience.int
        nextLevelExperience = max(1, json.next_level_experience.int)
        followNum = json.follow_num.int > 0 ? json.follow_num.int : json.follow.int
        fansNum = json.fans_num.int > 0 ? json.fans_num.int : json.fans.int
        feedNum = json.feed_num.int > 0 ? json.feed_num.int : json.feed.int
        likeNum = json.be_like_num.int > 0 ? json.be_like_num.int : json.likenum.int
        verifyLabel = json.verify_label.string
        verifyTitle = json.verify_title.string
        location = json.location.string
        let followFlag = json.isFollowed.exists
            ? json.isFollowed
            : (json.is_follow.exists ? json.is_follow : (json.isFollow.exists ? json.isFollow : json.userAction.follow))
        isFollowed = followFlag.bool || followFlag.int > 0
        gender = json.gender.int
        registerDate = json.regdate.date
        loginTime = json.logintime.date
        deviceTitle = json.device_title.string.isEmpty ? json.user_device.string : json.device_title.string
    }
}

public struct UserBrief: Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var avatar: String
    public var level: Int
    public var isFollowed: Bool
    public var bio: String
    public var verifyLabel: String
    public var fansNum: Int
    public var feedNum: Int

    public init(
        id: String,
        username: String,
        avatar: String = "",
        level: Int = 0,
        isFollowed: Bool = false,
        bio: String = "",
        verifyLabel: String = "",
        fansNum: Int = 0,
        feedNum: Int = 0
    ) {
        self.id = id
        self.username = username
        self.avatar = avatar
        self.level = level
        self.isFollowed = isFollowed
        self.bio = bio
        self.verifyLabel = verifyLabel
        self.fansNum = fansNum
        self.feedNum = feedNum
    }

    public init(json: JSON) {
        id = json.uid.exists ? json.uid.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        level = json.level.int
        let followFlag = json.isFollowed.exists
            ? json.isFollowed
            : (json.is_follow.exists ? json.is_follow : (json.isFollow.exists ? json.isFollow : json.userAction.follow))
        isFollowed = followFlag.bool || followFlag.int > 0
        bio = json.bio.string
        verifyLabel = json.verify_label.string
        fansNum = json.fans_num.int > 0 ? json.fans_num.int : json.fans.int
        feedNum = json.feed_num.int > 0 ? json.feed_num.int : json.feed.int
    }
}

public struct HomeBanner: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var image: String
    public var url: String

    public init(id: String, title: String, subtitle: String, image: String, url: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.url = url
    }
}

public struct HomeIconLink: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var image: String
    public var url: String
    public var subtitle: String

    public init(id: String, title: String, image: String, url: String, subtitle: String = "") {
        self.id = id
        self.title = title
        self.image = image
        self.url = url
        self.subtitle = subtitle
    }
}

public struct HomeSection: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var url: String
    public var style: String

    public init(id: String, title: String, subtitle: String, url: String, style: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.style = style
    }
}

public struct AppItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var logo: String
    public var score: String
    public var size: String
    public var version: String
    public var developer: String
    public var category: String
    public var downloadCount: String
    public var description: String
    public var commentCount: Int
    public var followCount: String
    public var packageName: String
    public var url: String
    public var updateFlag: String
    public var screenshots: [String]
    public var changelog: String

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.shorttitle.string.isEmpty ? json.subtitle.string : json.shorttitle.string
        logo = json.logo.string
        score = json.score.string
        size = json.apksize.string
        version = json.apkversionname.string.isEmpty ? json.version.string : json.apkversionname.string
        developer = json.developername.string
        category = json.catName.string
        downloadCount = json.downCount.string.isEmpty ? json.downnum.string : json.downCount.string
        description = json.description.string.isEmpty ? json.introduce.string : json.description.string
        commentCount = json.commentnum.int
        followCount = json.followCount.string
        packageName = json.packageName.string.isEmpty ? json.apkname.string : json.packageName.string
        url = json.url.string
        updateFlag = json.updateFlag.string
        changelog = json.changelog.string
        screenshots = json.screenshots.string
            .split(separator: ",")
            .map { coolapkNormalizedURL(String($0)) }
            .filter { !$0.isEmpty }
    }
}

public struct BrowseItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var logo: String
    public var url: String
    public var kindTitle: String
    public var dateline: Date?

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        url = json.url.string
        kindTitle = json.typeName.string.isEmpty ? json.target_type_title.string : json.typeName.string
        let stamp = json.dateline.exists ? json.dateline.double : json.lastupdate.double
        dateline = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }
}

public struct PearGoods: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var image: String
    public var price: String
    public var promoTitle: String
    public var mall: String
    public var category: String
    public var buyText: String
    public var buyURL: String
    public var detailURL: String

    public init(json: JSON) {
        let union = json.union_item_id.string
        let rawID = json.id.identifier
        id = !union.isEmpty ? union : (rawID.isEmpty ? json.title.string : rawID)
        title = json.title.string.isEmpty ? json.goods_title.string : json.title.string
        image = json.goods_pic.string
        let priceValue = json.goods_promo_price.double
        price = priceValue > 0 ? String(format: "¥%.2f", priceValue) : ""
        promoTitle = json.goods_promo_title.string
        mall = json.mall_title.string
        category = json.category_title.string
        buyText = json.goods_buy_text.string
        buyURL = json.goods_buy_url.string.isEmpty ? json.goods_url.string : json.goods_buy_url.string
        detailURL = json.goods_url.string
    }
}

public struct LiveTopic: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var summary: String
    public var cover: String
    public var startAt: Date?
    public var presenterUID: String

    public init(json: JSON) {
        id = json.id.identifier
        title = json.title.string
        summary = json.description.string
        cover = json.pic_url.string
        let stamp = json.live_time.double
        startAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        presenterUID = json.presenter_uid.string
    }
}

public struct ProductSpecEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public var label: String
    public var value: String
    public var group: String

    public init(id: String, label: String, value: String, group: String = "") {
        self.id = id
        self.label = label
        self.value = value
        self.group = group
    }
}

public struct ProductSpecSection: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var items: [ProductSpecEntry]

    public init(id: String, title: String, items: [ProductSpecEntry]) {
        self.id = id
        self.title = title
        self.items = items
    }

    /// Parses Coolapk's `m.coolapk.com/mp/product/configInfo` `dataRows` payload.
    public static func sections(fromConfigInfoJSON json: JSON) -> [ProductSpecSection] {
        let dataRowsDict = json.dataRows.dictionary
        guard !dataRowsDict.isEmpty else { return [] }

        var sections: [ProductSpecSection] = []
        for (sectionTitle, rowsJSON) in dataRowsDict.sorted(by: { $0.key < $1.key }) {
            let rows = rowsJSON.array
            var groupPath: [String] = []
            var entries: [ProductSpecEntry] = []

            for (rowIdx, row) in rows.enumerated() {
                let rowType = row.type.string
                if rowType == "groupData" {
                    let groupName = row.keyName.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !groupName.isEmpty {
                        let depth = max(1, row.depth.int)
                        while groupPath.count >= depth { groupPath.removeLast() }
                        while groupPath.count < depth - 1 { groupPath.append("") }
                        groupPath.append(groupName)
                    }
                } else if rowType == "itemData" {
                    let itemData = row.data
                    let name = itemData.title.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, let shown = displayValue(itemData.show_value) else { continue }
                    let unit = itemData.unit.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    let mainValue = (shown == "-" || unit.isEmpty) ? shown : "\(shown)\(unit)"
                    let addition = displayValue(itemData.addition_value)
                    let fullValue: String
                    if let addition, addition != "-", addition != mainValue {
                        fullValue = "\(mainValue)\n\(addition)"
                    } else {
                        fullValue = mainValue
                    }
                    let groupLabel = groupPath.filter { !$0.isEmpty }.joined(separator: " / ")
                    entries.append(ProductSpecEntry(
                        id: "cfginfo-\(sectionTitle)-\(rowIdx)-\(name)",
                        label: name,
                        value: fullValue,
                        group: groupLabel
                    ))
                }
            }

            if !entries.isEmpty {
                sections.append(ProductSpecSection(
                    id: "section-\(sectionTitle)",
                    title: sectionTitle,
                    items: entries
                ))
            }
        }
        return sections
    }

    private static func displayValue(_ json: JSON) -> String? {
        guard !json.isNull else { return nil }
        let text: String
        switch json.value {
        case .string, .number, .bool:
            text = json.string
        case .array:
            text = json.array.compactMap { displayValue($0) }.joined(separator: " / ")
        case .object:
            text = json.dictionary
                .sorted(by: { $0.key < $1.key })
                .compactMap { k, v in displayValue(v).map { "\(k): \($0)" } }
                .joined(separator: " / ")
        case .null:
            text = ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ProductConfigVariant: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var priceText: String
    public var releaseTime: String
    public var keywords: String
    public var description: String
    public var specs: [ProductSpecEntry]

    public init(
        id: String,
        title: String,
        priceText: String = "",
        releaseTime: String = "",
        keywords: String = "",
        description: String = "",
        specs: [ProductSpecEntry] = []
    ) {
        self.id = id
        self.title = title
        self.priceText = priceText
        self.releaseTime = releaseTime
        self.keywords = keywords
        self.description = description
        self.specs = specs
    }

    public init(json: JSON, index: Int) {
        let rawID = json.id.exists ? json.id.identifier : json.config_id.identifier
        id = rawID.isEmpty ? "cfg-\(index)" : rawID
        title = [json.title.string, json.version_name.string, json.config_name.string, json.name.string]
            .first { !$0.isEmpty } ?? "版本 \(index + 1)"
        if json.price.double > 0 {
            priceText = "¥\(Int(json.price.double))"
        } else {
            priceText = [json.price_text.string, json.price.string, json.rmb_price.string].first { !$0.isEmpty } ?? ""
        }
        releaseTime = json.release_time.string
        keywords = json.keywords.string
        description = json.description.string
        specs = Self.extractSpecEntries(from: json, prefix: id)
    }

    public static func extractSpecEntries(from json: JSON, prefix: String) -> [ProductSpecEntry] {
        var entries: [ProductSpecEntry] = []
        var seenLabels = Set<String>()

        func appendEntry(_ label: String, _ value: String) {
            let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !l.isEmpty, !v.isEmpty, seenLabels.insert(l).inserted else { return }
            entries.append(ProductSpecEntry(id: "\(prefix)-\(entries.count)-\(l)", label: l, value: v))
        }

        let candidates: [(JSON, String)] = [
            (json.config_data.parsed.exists ? json.config_data.parsed : json.config_data, "cd"),
            (json.param_list.parsed.exists ? json.param_list.parsed : json.param_list, "pl"),
            (json.params.parsed.exists ? json.params.parsed : json.params, "pr")
        ]
        for (source, _) in candidates where !source.isNull {
            for item in source.array {
                if item.isObject {
                    let lbl = [item.title.string, item.name.string, item.key.string, item.label.string]
                        .first { !$0.isEmpty } ?? ""
                    let val = [
                        item.dictionary["value"]?.string ?? "",
                        item.content.string,
                        item.desc.string,
                        item.text.string
                    ].first { !$0.isEmpty } ?? ""
                    appendEntry(lbl, val)
                    for child in item.entities.array {
                        let cLbl = [child.title.string, child.name.string, child.key.string].first { !$0.isEmpty } ?? ""
                        let cVal = [
                            child.dictionary["value"]?.string ?? "",
                            child.content.string,
                            child.description.string
                        ].first { !$0.isEmpty } ?? ""
                        appendEntry(cLbl, cVal)
                    }
                }
            }
            let dict = source.dictionary
            if !dict.isEmpty {
                for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                    let valStr = v.string
                    if !valStr.isEmpty {
                        appendEntry(k, valStr)
                    } else if !v.array.isEmpty {
                        let joined = v.array.compactMap { elem in
                            let sub = elem.string.isEmpty ? elem.title.string : elem.string
                            return sub.isEmpty ? nil : sub
                        }.joined(separator: " / ")
                        appendEntry(k, joined)
                    }
                }
            }
        }

        let knownFields: [(String, [String])] = [
            ("处理器 / SoC", [json.cpu.string, json.soc.string]),
            ("内存 / 存储", [
                [json.ram.string, json.rom.string].filter { !$0.isEmpty }.joined(separator: " + "),
                json.memory.string
            ]),
            ("屏幕参数", [json.screen.string, json.screen_size.string, json.display.string]),
            ("电池与充电", [json.battery.string, json.charge.string]),
            ("影像系统", [json.camera.string]),
            ("操作系统", [json.os.string, json.system.string]),
            ("机身尺寸 / 重量", [[json.size.string, json.weight.string].filter { !$0.isEmpty }.joined(separator: " · ")]),
            ("参考价格", [json.price_text.string, json.price.string]),
            ("发布时间", [json.release_time.string]),
            ("版本特性", [json.keywords.string])
        ]
        for (label, vals) in knownFields {
            if let first = vals.first(where: { !$0.isEmpty }) {
                appendEntry(label, first)
            }
        }

        return entries
    }
}

public struct ProductItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var logo: String
    public var cover: String
    public var description: String
    public var recommendReason: String
    public var priceText: String
    public var releaseTime: String
    public var score: String
    public var followNum: Int
    public var commentNum: Int
    public var feedNum: Int
    public var hotNum: Int
    public var isFollowed: Bool
    public var url: String
    public var tabs: [HomeSection]
    public var configVariants: [ProductConfigVariant]
    public var specEntries: [ProductSpecEntry]

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.sub_title.string.isEmpty ? json.description.string : json.sub_title.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        cover = json.cover.string.isEmpty ? (json.coverArr.array.first?.string ?? "") : json.cover.string
        description = json.description.string.isEmpty ? json.introduce.string : json.description.string
        recommendReason = json.recommend_reason.string
        if json.price_min.double > 0 {
            let minP = Int(json.price_min.double)
            let maxP = Int(json.price_max.double)
            priceText = maxP > minP ? "¥\(minP)-\(maxP)" : "¥\(minP) 起"
        } else {
            priceText = json.price_text.string
        }
        releaseTime = json.release_time.string
        score = json.score.string.isEmpty
            ? (json.avg_score.string.isEmpty ? json.star_average_score.string : json.avg_score.string)
            : json.score.string
        followNum = json.follow_num.int
        commentNum = json.feed_comment_num.int > 0 ? json.feed_comment_num.int : json.comment_num.int
        feedNum = json.feed_num.int
        hotNum = json.hot_num.int
        let followFlag = json.isFollowed.exists
            ? json.isFollowed
            : (json.is_follow.exists ? json.is_follow : (json.userAction.follow.exists ? json.userAction.follow : json.follow))
        isFollowed = followFlag.bool || followFlag.int > 0
        url = json.url.string
        let rawTabs = json.tabList.array
        tabs = rawTabs.enumerated().compactMap { idx, entry in
            let tabTitle = entry.title.string
            let tabURL = entry.url.string.isEmpty ? entry.page_name.string : entry.url.string
            guard !tabTitle.isEmpty, !tabURL.isEmpty else { return nil }
            return HomeSection(
                id: "ptab-\(idx)-\(entry.entityId.identifier)-\(tabTitle)",
                title: tabTitle,
                subtitle: entry.sub_title.string,
                url: tabURL,
                style: entry.pic.string
            )
        }

        let variantArrays = [
            json.configRows.array,
            json.configList.array,
            json.version_list.array,
            json.skuRows.array,
            json.config_data.array,
            json.config_data.parsed.array
        ]
        if let found = variantArrays.first(where: { !$0.isEmpty }) {
            configVariants = found.enumerated().map { ProductConfigVariant(json: $0.element, index: $0.offset) }
        } else {
            configVariants = []
        }
        specEntries = ProductConfigVariant.extractSpecEntries(from: json, prefix: id)
    }
}

public struct TopicItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var description: String
    public var logo: String
    public var feedNum: Int
    public var followNum: Int
    public var hotNum: Int
    public var feedNumText: String
    public var hotNumText: String
    public var isFollowed: Bool
    public var selectedTab: String
    public var tabs: [HomeSection]

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        description = json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        let rawFeedTxt = [
            json.commentnum_txt.string,
            json.feed_comment_num_txt.string,
            json.feed_num_txt.string
        ].first { !$0.isEmpty } ?? ""
        let rawHotTxt = json.hot_num_txt.string
        feedNum = [
            json.feed_num.int,
            json.commentnum.int,
            json.feed_comment_num.int,
            json.commentCount.int,
            json.comment_num.int,
            Self.parseCompactCount(rawFeedTxt)
        ].first { $0 > 0 } ?? 0
        followNum = [json.follow_num.int, json.follownum.int].first { $0 > 0 } ?? 0
        hotNum = [json.hot_num.int, Self.parseCompactCount(rawHotTxt)].first { $0 > 0 } ?? 0
        feedNumText = rawFeedTxt
        hotNumText = rawHotTxt
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
            || json.extraData.parsed.showCancelFollowMenu.int > 0
        selectedTab = json.selectedTab.string.isEmpty ? json.selected_tab.string : json.selectedTab.string
        var parsedTabs: [HomeSection] = []
        var seenTabIDs = Set<String>()
        for (idx, entry) in json.tabList.array.enumerated() {
            let tabTitle = entry.title.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let pageName = entry.page_name.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawURL = entry.url.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let tabURL = rawURL.isEmpty ? pageName : rawURL
            guard !tabTitle.isEmpty, (!tabURL.isEmpty || !pageName.isEmpty) else { continue }
            let baseID = !pageName.isEmpty ? pageName : tabURL
            let uniqueID = seenTabIDs.insert(baseID).inserted ? baseID : "\(baseID)-\(idx)"
            parsedTabs.append(HomeSection(
                id: uniqueID,
                title: tabTitle,
                subtitle: pageName,
                url: tabURL,
                style: entry.pic.string
            ))
        }
        tabs = parsedTabs
    }

    private static func parseCompactCount(_ raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return 0 }
        if trimmed.hasSuffix("亿"), let val = Double(trimmed.dropLast()) {
            return Int(val * 100_000_000)
        }
        if trimmed.hasSuffix("万") || trimmed.hasSuffix("w"), let val = Double(trimmed.dropLast()) {
            return Int(val * 10_000)
        }
        if trimmed.hasSuffix("k"), let val = Double(trimmed.dropLast()) {
            return Int(val * 1_000)
        }
        return Int(trimmed) ?? Int(Double(trimmed) ?? 0)
    }
}

public struct CollectionItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var description: String
    public var logo: String
    public var username: String
    public var avatar: String
    public var uid: String
    public var itemNum: Int
    public var followNum: Int
    public var likeNum: Int
    public var isFollowed: Bool
    public var isBeCollected: Bool

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.sub_title.string
        description = json.description.string.isEmpty ? json.intro.string : json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        username = json.username.string.isEmpty ? json.userInfo.username.string : json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.userInfo.userAvatar.string : json.userAvatar.string
        uid = json.uid.identifier.isEmpty ? json.userInfo.uid.identifier : json.uid.identifier
        itemNum = json.item_num.int
        followNum = json.follow_num.int
        likeNum = json.like_num.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
        isBeCollected = json.isBeCollected.int > 0 || json.isBeCollected.bool
    }
}

public struct DyhItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var description: String
    public var logo: String
    public var username: String
    public var avatar: String
    public var uid: String
    public var followNum: Int
    public var likeNum: Int
    public var isFollowed: Bool

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.dyh_id.identifier
        title = json.title.string
        description = json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        username = json.username.string
        avatar = json.userAvatar.string
        uid = json.uid.identifier
        followNum = json.follownum.int
        likeNum = json.likenum.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0 || json.is_follow.int > 0
    }
}

public struct EventItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var description: String
    public var cover: String
    public var url: String
    public var startTimeText: String
    public var statusText: String
    public var joinNum: Int

    public init(
        id: String,
        title: String = "",
        description: String = "",
        cover: String = "",
        url: String = "",
        startTimeText: String = "",
        statusText: String = "",
        joinNum: Int = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.cover = cover
        self.url = url
        self.startTimeText = startTimeText
        self.statusText = statusText
        self.joinNum = joinNum
    }

    public init(json: JSON) {
        let rawID = json.id.exists ? json.id.identifier : json.entityId.identifier
        let rawURL = json.url.string
        if !rawID.isEmpty {
            id = rawID
        } else if let range = rawURL.range(of: "/event/") {
            let tail = String(rawURL[range.upperBound...])
            id = String(tail.prefix { $0 != "?" && $0 != "/" })
        } else {
            id = rawURL
        }
        title = json.title.string
        description = [json.description.string, json.intro.string, json.content.string, json.message.string, json.sub_title.string]
            .first { !$0.isEmpty } ?? ""
        cover = [json.pic.string, json.cover.string, json.logo.string]
            .first { !$0.isEmpty } ?? ""
        url = rawURL
        startTimeText = json.dateline_text.string.isEmpty ? json.start_time_text.string : json.dateline_text.string
        statusText = json.status_text.string.isEmpty ? json.label.string : json.status_text.string
        joinNum = json.join_num.int > 0 ? json.join_num.int : json.follow_num.int
    }
}

public struct HomeTab: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var pageName: String
    public var logo: String
    public var link: String

    public init(id: String, title: String, pageName: String, logo: String = "", link: String = "") {
        self.id = id
        self.title = title
        self.pageName = pageName
        self.logo = logo
        self.link = link
    }
}

public struct SidebarSection: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var tabs: [HomeTab]

    public init(id: String, title: String, tabs: [HomeTab]) {
        self.id = id
        self.title = title
        self.tabs = tabs
    }
}

public enum HomeFeedRow: Identifiable, Hashable, Sendable {
    case feed(FeedItem)
    case product(ProductItem)
    case topic(TopicItem)
    case user(UserBrief)
    case app(AppItem)
    case banners(String, [HomeBanner])
    case icons(String, [HomeIconLink])
    case sections(String, [HomeSection])
    case text(String, String)
    case sectionTitle(key: String, title: String, url: String, subtitle: String)
    case linkBar(String, [HomeSection])
    case linkList(String, [HomeSection])
    case columnTabs(String, [HomeSection])
    case loginPrompt(String, String)
    case notice(String, String)
    case goods(String, [PearGoods])
    case lives(String, [LiveTopic])
    case browse(BrowseItem)
    case collection(CollectionItem)
    case event(EventItem)
    case dyh(DyhItem)

    public var id: String {
        switch self {
        case let .feed(item): return "feed-\(item.id)"
        case let .product(item): return "product-\(item.id)"
        case let .topic(item): return "topic-\(item.id)"
        case let .user(item): return "user-\(item.id)"
        case let .app(item): return "app-\(item.id)"
        case let .banners(key, _): return "banner-\(key)"
        case let .icons(key, _): return "icons-\(key)"
        case let .sections(key, _): return "sections-\(key)"
        case let .text(key, _): return "text-\(key)"
        case let .sectionTitle(key, _, _, _): return "section-\(key)"
        case let .linkBar(key, _): return "linkbar-\(key)"
        case let .linkList(key, _): return "linklist-\(key)"
        case let .columnTabs(key, _): return "columns-\(key)"
        case let .loginPrompt(key, _): return "login-\(key)"
        case let .notice(key, _): return "notice-\(key)"
        case let .goods(key, _): return "goods-\(key)"
        case let .lives(key, _): return "lives-\(key)"
        case let .browse(item): return "browse-\(item.id)"
        case let .collection(item): return "collection-\(item.id)"
        case let .event(item): return "event-\(item.id)"
        case let .dyh(item): return "dyh-\(item.id)"
        }
    }

    public var date: Date? {
        if case let .feed(item) = self { return item.dateline }
        return nil
    }
}
