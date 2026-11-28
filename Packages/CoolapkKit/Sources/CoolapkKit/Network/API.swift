import Foundation

public enum API: Sendable {
    private static var client: CoolapkClient { CoolapkClient.shared }

    // MARK: - Home & Discovery Timelines

    public static func tabConfiguration() async throws -> [SidebarSection] {
        let json = try await client.get("/v6/main/init", ["t": String(Int(Date().timeIntervalSince1970))])
        var sections: [SidebarSection] = []
        for card in json.data.array {
            let title = card.title.string
            var tabs: [HomeTab] = []
            for entity in card.entities.array {
                let pageName = entity.page_name.string
                guard !pageName.isEmpty else { continue }
                tabs.append(HomeTab(
                    id: pageName,
                    title: entity.title.string,
                    pageName: pageName,
                    logo: entity.logo.string,
                    link: entity.url.string
                ))
            }
            guard !tabs.isEmpty else { continue }
            sections.append(SidebarSection(id: title, title: title, tabs: tabs))
        }
        return sections
    }

    public static func hotSearchWords() async throws -> [String] {
        let json = try await client.get("/v6/main/init", ["t": String(Int(Date().timeIntervalSince1970))])
        var words: [String] = []
        for card in json.data.array {
            if card.entityTemplate.string == "searchWordCard" || card.title.string.contains("热搜") {
                words.append(contentsOf: card.entities.array.map(\.title.string).filter { !$0.isEmpty })
            }
        }
        if words.isEmpty {
            words = json.data.array.first?.entities.array.map(\.title.string).filter { !$0.isEmpty } ?? []
        }
        return words
    }

    public static func homeFeed(page: Int) async throws -> [HomeFeedRow] {
        let now = String(Int(Date().timeIntervalSince1970))
        async let v8Task = client.get(
            "/v6/main/indexV8",
            [
                "page": String(page),
                "firstLaunch": "0",
                "installTime": now,
                "ids": "",
                "t": now
            ],
            base: CoolapkClient.api2Base
        )
        let json = try await v8Task
        var parsed = rows(from: json.data.array)

        // When /v6/main/indexV8 on page 1 returns only 1 top banner item (or splits banners across headline),
        // supplement with top banners from /v6/main/headline so the home top carousel always has a multi-card stack.
        if page == 1 {
            let existingBannerCount = parsed.reduce(0) { acc, row in
                if case let .banners(_, b) = row { return acc + b.count }
                return acc
            }
            if existingBannerCount <= 1,
               let headlineJSON = try? await client.get("/v6/main/headline", ["page": "1", "t": now], clearProofOnCaptcha: false) {
                let headlineRows = rows(from: headlineJSON.data.array)
                var extraBanners: [HomeBanner] = []
                for hRow in headlineRows {
                    if case let .banners(_, bList) = hRow {
                        extraBanners.append(contentsOf: bList)
                    } else if case let .sections(_, sList) = hRow, sList.count > 1 {
                        for (sIdx, sec) in sList.enumerated() where !sec.style.isEmpty {
                            extraBanners.append(HomeBanner(
                                id: "hl-sec-\(sIdx)-\(sec.id)",
                                title: sec.title,
                                subtitle: sec.subtitle,
                                image: sec.style,
                                url: sec.url
                            ))
                        }
                    }
                }
                if !extraBanners.isEmpty {
                    if let firstBannerIdx = parsed.firstIndex(where: {
                        if case .banners = $0 { return true }
                        return false
                    }), case let .banners(key, currentBanners) = parsed[firstBannerIdx] {
                        var combined = currentBanners
                        var seen = Set(currentBanners.map(\.image))
                        for b in extraBanners where seen.insert(b.image).inserted {
                            combined.append(b)
                        }
                        parsed[firstBannerIdx] = .banners(key, combined)
                    } else if extraBanners.count > 1 {
                        parsed.insert(.banners("banner-top-hl", extraBanners), at: 0)
                    }
                }
            }
        }
        return parsed
    }

    public static func headlineFeed(page: Int) async throws -> [HomeFeedRow] {
        var loaded: [HomeFeedRow] = []
        for attempt in 0..<3 {
            let json = try await client.get("/v6/main/headline", ["page": String(page), "t": String(Int(Date().timeIntervalSince1970))])
            loaded = rows(from: json.data.array)
            if !loaded.isEmpty || page > 1 { break }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 350_000_000) }
        }
        return loaded
    }

    public static func dyhSubscribe(page: Int) async throws -> [HomeFeedRow] {
        do {
            let json = try await client.get("/v6/user/dyhSubscribe", ["page": String(page), "t": String(Int(Date().timeIntervalSince1970))])
            let items = rows(from: json.data.array)
            if !items.isEmpty || page > 1 { return items }
        } catch {
            // Fall back cleanly to public dyh discovery or dyh tab page when guest/expired/empty
        }
        if let pub = try? await client.get("/v6/dyh/list", ["page": String(page)]) {
            let parsed = rows(from: pub.data.array)
            if !parsed.isEmpty { return parsed }
            let mapped = pub.data.array.compactMap { item -> HomeFeedRow? in
                let dyh = DyhItem(json: item)
                return dyh.id.isEmpty ? nil : .dyh(dyh)
            }
            if !mapped.isEmpty { return mapped }
        }
        return (try? await pageFeed(pageName: "V9_HOME_TAB_DYH", page: page)) ?? []
    }

    public static func coolPic(tag: String = "全部", type: String = "recommend", page: Int) async throws -> [HomeFeedRow] {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiTag = (trimmedTag == "全部" || trimmedTag.lowercased() == "all") ? "" : trimmedTag

        // 1. Try /v6/picture/list with normalized empty tag for "全部" (matching coolapk-desktop get_picture_list)
        let candidateQueries: [[String: String]] = [
            ["tag": apiTag, "type": type, "page": String(page)],
            ["tag": apiTag, "type": type, "feedType": "picture", "page": String(page)],
            ["tag": trimmedTag, "type": type, "page": String(page)]
        ]
        for query in candidateQueries {
            if let json = try? await client.get("/v6/picture/list", query) {
                let mapped = rows(from: json.data.array)
                if !mapped.isEmpty { return mapped }
            }
        }

        // 2. Fallback: V11_FIND_COOLPIC sub-tabs or dataList `#/picture/list` / `#/feed/coolPictureList`
        let sortListType: String = {
            switch type.lowercased() {
            case "new", "latest", "dateline_desc": return "dateline_desc"
            case "hot", "popular", "hot_num": return "popular"
            default: return "recommend"
            }
        }()
        let dataListCandidates: [(String, [String: String])] = [
            ("/picture/list", ["tag": apiTag, "type": type, "listType": sortListType]),
            ("/feed/coolPictureList", ["tag": apiTag, "type": type, "listType": sortListType]),
            ("V11_FIND_COOLPIC", ["type": type, "listType": sortListType])
        ]
        for (urlPath, extra) in dataListCandidates {
            if let items = try? await dataListFollowingFlexList(url: urlPath, page: page, extra: extra) {
                let mapped = rows(from: items).filter { row in
                    switch row {
                    case .linkBar, .columnTabs: return false
                    default: return true
                    }
                }
                if !mapped.isEmpty { return mapped }
            }
        }
        return []
    }

    public static let followPageName = "V9_HOME_TAB_FOLLOW"

    public static func pageFeed(pageName: String, page: Int, type: String? = nil) async throws -> [HomeFeedRow] {
        var extra: [String: String] = [:]
        if let type { extra["type"] = type }
        let items = try await dataListFollowingFlexList(url: pageName, page: page, extra: extra)
        return rows(from: items)
    }

    public static func linkFeed(link: String, page: Int) async throws -> [HomeFeedRow] {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "/user/dyhsubscribe" || lower == "/v6/user/dyhsubscribe" || lower == "#/user/dyhsubscribe" {
            return try await dyhSubscribe(page: page)
        }
        if lower.contains("dyhfollowlist") {
            let dyhs = try await followedDyhs(page: page)
            return dyhs.map { .dyh($0) }
        }
        if trimmed.contains("数码测评") || lower.contains("/board/数码测评") {
            return try await reviewFeeds(page: page)
        }
        if let boardRange = trimmed.range(of: "/board/") {
            let rawTag = String(trimmed[boardRange.upperBound...])
                .split(whereSeparator: { $0 == "?" || $0 == "&" || $0 == "/" })
                .first
                .map(String.init) ?? ""
            let decodedTag = (rawTag.removingPercentEncoding ?? rawTag).trimmingCharacters(in: .whitespacesAndNewlines)
            if !decodedTag.isEmpty {
                let tagRows = (try? await topicFeeds(tag: decodedTag, page: page)) ?? []
                if !tagRows.isEmpty { return tagRows }
                let searchJSON = (try? await search(keyword: decodedTag, type: "feed", page: page)) ?? []
                return rows(from: searchJSON)
            }
        }
        if lower.contains("v11_find_good_things") || lower.contains("v11_find_goods") || lower == "#/goods/feedlist" || lower == "/v6/goodslist/list" {
            return try await goodsRecommendationFeed(page: page)
        }
        // User followList / fansList links (e.g. from UserDetailView "TA关注的人 -> 查看全部")
        if lower.contains("/user/followlist") || lower.contains("/user/fanslist") {
            let parsed = parsePageLink(trimmed)
            let isFans = lower.contains("fanslist")
            let targetUID: String = {
                if let u = parsed.extra["uid"], !u.isEmpty { return u }
                if let comps = URLComponents(string: trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed),
                   let u = comps.queryItems?.first(where: { $0.name == "uid" || $0.name == "id" })?.value,
                   !u.isEmpty {
                    return u
                }
                return ""
            }()
            if !targetUID.isEmpty {
                let users = try await userList(uid: targetUID, followers: isFans, page: page)
                return users.map { .user($0) }
            }
        }
        // User digital equipment / product list (`#/product/productList?type=owner&uid=...` or `/v6/user/productList`)
        if lower.contains("user/productlist") || (lower.contains("product/productlist") && (lower.contains("type=owner") || lower.contains("type=wish") || lower.contains("type=buy") || lower.contains("uid="))) {
            let parsed = parsePageLink(trimmed)
            let targetUID = parsed.extra["uid"] ?? ""
            let pType = parsed.extra["type"] ?? "owner"
            return try await userEquipmentFeed(uid: targetUID, type: pType, page: page)
        }
        if trimmed.hasPrefix("/v6/") {
            let parsed = parsePageLink(trimmed)
            var params = parsed.extra
            params["page"] = String(page)
            let json = try await client.get(parsed.url, params)
            return rows(from: json.data.array)
        }
        let parsed = parsePageLink(trimmed)
        let items = try await dataListFollowingFlexList(url: parsed.url, page: page, extra: parsed.extra)
        return rows(from: items)
    }

    public static func topicVerticalTabs() async throws -> [HomeSection] {
        let items = try await client.dataList(url: "V11_VERTICAL_TOPIC", page: 1, extra: ["title": "话题"])
        var sections: [HomeSection] = []
        for (idx, item) in items.enumerated() {
            for (offset, entity) in item.entities.array.enumerated() {
                let title = entity.title.string
                let url = entity.url.string
                if !title.isEmpty && !url.isEmpty {
                    sections.append(HomeSection(
                        id: "vtopic-\(idx)-\(offset)-\(entity.entityId.identifier)",
                        title: title,
                        subtitle: entity.sub_title.string,
                        url: url,
                        style: entity.pic.string
                    ))
                }
            }
        }
        return sections
    }

    public static func productCategoryTabs() async throws -> [HomeSection] {
        let json = try await client.get("/v6/product/categoryList")
        var sections: [HomeSection] = []
        for (idx, item) in json.data.array.enumerated() {
            let title = item.title.string
            let url = item.url.string
            if !title.isEmpty && !url.isEmpty {
                sections.append(HomeSection(
                    id: "pcat-\(idx)-\(item.entityId.identifier)-\(title)",
                    title: title,
                    subtitle: item.sub_title.string,
                    url: url,
                    style: item.logo.string.isEmpty ? item.pic.string : item.logo.string
                ))
            }
            for (offset, entity) in item.entities.array.enumerated() {
                let eTitle = entity.title.string
                let eURL = entity.url.string
                if !eTitle.isEmpty && !eURL.isEmpty {
                    sections.append(HomeSection(
                        id: "pcat-\(idx)-\(offset)-\(entity.entityId.identifier)-\(eTitle)",
                        title: eTitle,
                        subtitle: entity.sub_title.string,
                        url: eURL,
                        style: entity.logo.string.isEmpty ? entity.pic.string : entity.logo.string
                    ))
                }
            }
        }
        return sections
    }

    public static func productFeed(pageLink: String, page: Int) async throws -> [HomeFeedRow] {
        let parsed = parsePageLink(pageLink)
        let items = try await dataListFollowingFlexList(url: parsed.url, page: page, extra: parsed.extra)
        return rows(from: items)
    }

    /// Loads product discussion/review feeds reliably across Coolapk's product endpoints.
    public static func productFeeds(
        productID: String,
        title: String = "",
        tabURL: String? = nil,
        listType: String = "lastupdate_desc",
        page: Int
    ) async throws -> [HomeFeedRow] {
        let cleanedTabURL = tabURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowerTab = cleanedTabURL.lowercased()
        let isConfigTab = lowerTab.contains("config") || lowerTab.contains("param")
        if isConfigTab {
            return []
        }

        if !cleanedTabURL.isEmpty, cleanedTabURL != "/product/\(productID)" {
            if cleanedTabURL.hasPrefix("/v6/") {
                let json = try? await client.get(cleanedTabURL, ["id": productID, "page": String(page), "listType": listType])
                if let mapped = json.map({ rows(from: $0.data.array) }), !mapped.isEmpty {
                    return mapped
                }
            } else {
                let loaded = (try? await linkFeed(link: cleanedTabURL, page: page)) ?? []
                if !loaded.isEmpty { return loaded }
            }
        }

        // Endpoint 1: V11/V9 dataList product feed list
        let candidateLinks = [
            "#/feed/productFeedList?id=\(productID)&type=feed&listType=\(listType)",
            "#/product/feedList?id=\(productID)&type=feed&listType=\(listType)"
        ]
        for candidate in candidateLinks {
            let parsed = parsePageLink(candidate)
            if let items = try? await client.dataList(url: parsed.url, page: page, extra: parsed.extra) {
                let mapped = rows(from: items)
                if !mapped.isEmpty { return mapped }
            }
        }

        // Endpoint 2: Direct /v6/product/feedList
        if let json = try? await client.get("/v6/product/feedList", [
            "id": productID,
            "type": "feed",
            "listType": listType,
            "page": String(page)
        ]) {
            let mapped = rows(from: json.data.array)
            if !mapped.isEmpty { return mapped }
        }

        // Endpoint 3: Fallback to topic/device tag feed list by product title
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            if let tagRows = try? await topicFeeds(tag: cleanTitle, page: page, listType: listType), !tagRows.isEmpty {
                return tagRows
            }
        }

        return []
    }

    /// Fetches detailed parameter sections for a specific product configuration/SKU from `m.coolapk.com/mp/product/configInfo`.
    public static func productConfigInfo(configID: String) async -> [ProductSpecSection] {
        guard !configID.isEmpty, configID != "0" else { return [] }
        guard let json = try? await client.get(
            "https://m.coolapk.com/mp/product/configInfo",
            ["id": configID],
            clearProofOnCaptcha: false
        ) else {
            return []
        }
        return ProductSpecSection.sections(fromConfigInfoJSON: json)
    }

    public static func productConfig(
        productID: String,
        tabURL: String? = nil
    ) async -> (variants: [ProductConfigVariant], specs: [ProductSpecEntry], rawRows: [HomeFeedRow]) {
        var variants: [ProductConfigVariant] = []
        var specs: [ProductSpecEntry] = []

        func ingestConfigJSON(_ data: JSON) {
            let arr = data.array
            if !arr.isEmpty {
                let realConfigItems = arr.filter { elem in
                    guard elem.isObject else { return false }
                    // Exclude unrelated recommendation cards ("同价位", "同SoC", "同系列", "版本配置" headers).
                    return elem.entityType.string != "card"
                }
                let parsedVariants = realConfigItems.enumerated().compactMap { idx, elem -> ProductConfigVariant? in
                    let variant = ProductConfigVariant(json: elem, index: idx)
                    return (variant.title.isEmpty && variant.specs.isEmpty) ? nil : variant
                }
                if !parsedVariants.isEmpty && variants.isEmpty {
                    variants = parsedVariants
                }
                for (idx, elem) in realConfigItems.enumerated() {
                    let extracted = ProductConfigVariant.extractSpecEntries(from: elem, prefix: "cfg-arr-\(idx)")
                    for entry in extracted where !specs.contains(where: { $0.label == entry.label }) {
                        specs.append(entry)
                    }
                    let directTitle = [elem.title.string, elem.name.string, elem.label.string].first { !$0.isEmpty } ?? ""
                    let directVal = [
                        elem.dictionary["value"]?.string ?? "",
                        elem.content.string,
                        elem.description.string
                    ].first { !$0.isEmpty } ?? ""
                    if !directTitle.isEmpty && !directVal.isEmpty && !specs.contains(where: { $0.label == directTitle }) {
                        specs.append(ProductSpecEntry(id: "cfg-kv-\(idx)-\(directTitle)", label: directTitle, value: directVal))
                    }
                }
            } else if data.isObject {
                let parsed = ProductItem(json: data)
                if !parsed.configVariants.isEmpty && variants.isEmpty {
                    variants = parsed.configVariants
                }
                for entry in parsed.specEntries where !specs.contains(where: { $0.label == entry.label }) {
                    specs.append(entry)
                }
            }
        }

        let candidates: [(String, [String: String])] = [
            ("/v6/product/configList", ["id": productID]),
            ("/v6/product/configList", ["productId": productID]),
            ("/v6/product/detail", ["id": productID, "type": "config"])
        ]
        for (path, params) in candidates {
            if let json = try? await client.get(path, params, clearProofOnCaptcha: false) {
                ingestConfigJSON(json.data)
                if !variants.isEmpty && !specs.isEmpty { break }
            }
        }

        return (variants, specs, [])
    }

    private static func parsePageLink(_ link: String) -> (url: String, extra: [String: String]) {
        var clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("coolapk://") {
            clean = String(clean.dropFirst("coolapk://".count))
            if !clean.hasPrefix("/") { clean = "/" + clean }
        }
        if clean.hasPrefix("#/page?") || clean.hasPrefix("#page?") {
            clean = String(clean.dropFirst())
        }
        var resolvedTarget = ""
        var extra: [String: String] = [:]
        if clean.hasPrefix("/page?") || clean.hasPrefix("page?"),
           let components = URLComponents(string: clean.hasPrefix("/") ? clean : "/\(clean)"),
           let queryItems = components.queryItems {
            for item in queryItems {
                guard let value = item.value, !value.isEmpty else { continue }
                if item.name == "url" {
                    resolvedTarget = value.replacingOccurrences(of: "#", with: "")
                } else {
                    extra[item.name] = value
                }
            }
        } else {
            resolvedTarget = pageTarget(from: clean)
        }

        // Official Coolapk APK & coolapk-desktop (`client.rs:get_product_subtab_feeds`) requirement:
        // When requesting product subtabs (`/product/feedList?type=subTabFeed&id=...&subId=6`),
        // `/v6/page/dataList` requires `url=/page?url=/product/feedList` and top-level query params
        // `type=subTabFeed`, `withSortCard=1`, `withSubTabFeedCard=1`, `ignoreEntityById=1`, `id=...`, `subId=...`
        // so that the server attaches the structured subTabFeedCard (e.g. 到手价 final_price & SKU config).
        let strippedTarget = resolvedTarget.hasPrefix("#") ? String(resolvedTarget.dropFirst()) : resolvedTarget
        if strippedTarget.hasPrefix("/product/feedList"),
           let targetComps = URLComponents(string: strippedTarget),
           let targetQuery = targetComps.queryItems,
           targetQuery.contains(where: { $0.name == "subId" || ($0.name == "type" && $0.value == "subTabFeed") }) {
            for item in targetQuery {
                if let value = item.value, !value.isEmpty, extra[item.name] == nil {
                    extra[item.name] = value
                }
            }
            if extra["type"] == nil { extra["type"] = "subTabFeed" }
            if extra["cacheExpires"] == nil { extra["cacheExpires"] = "60" }
            if extra["withSortCard"] == nil { extra["withSortCard"] = "1" }
            extra["withSubTabFeedCard"] = "1"
            if extra["ignoreEntityById"] == nil { extra["ignoreEntityById"] = "1" }
            return ("/page?url=/product/feedList", extra)
        }

        return (resolvedTarget, extra)
    }

    private static func dataListFollowingFlexList(
        url: String,
        page: Int,
        extra: [String: String]
    ) async throws -> [JSON] {
        var currentItems = try await client.dataList(url: url, page: page, extra: extra)
        var visited: Set<String> = [url]
        var hops = 0
        while hops < 3 {
            guard let configCard = currentItems.first(where: {
                let tpl = $0.entityTemplate.string.lowercased()
                let typ = $0.entityType.string.lowercased()
                return tpl == "configcard" || typ == "configcard"
            }) else {
                break
            }
            let cfgExtra = configCard.extraDataArr.isObject ? configCard.extraDataArr : configCard.extraData.parsed
            let isFlex = cfgExtra.flexList.int == 1 || cfgExtra.flexList.string == "1" || cfgExtra.flexList.bool
            let flexURL = cfgExtra.url.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isFlex, !flexURL.isEmpty, !visited.contains(flexURL) else { break }
            visited.insert(flexURL)
            hops += 1
            let parsedFlex = parsePageLink(flexURL)
            var mergedExtra = extra
            for (k, v) in parsedFlex.extra {
                mergedExtra[k] = v
            }
            let nonConfigPrefix = currentItems.filter {
                let tpl = $0.entityTemplate.string.lowercased()
                let typ = $0.entityType.string.lowercased()
                return tpl != "configcard" && typ != "configcard"
            }
            let nextItems = try await client.dataList(url: parsedFlex.url, page: page, extra: mergedExtra)
            currentItems = (page == 1 ? nonConfigPrefix : []) + nextItems
        }
        return currentItems
    }

    public static func pageTarget(from link: String) -> String {
        var target = link
        if let range = target.range(of: "url=") {
            target = String(target[range.upperBound...])
            if let amp = target.firstIndex(of: "&") { target = String(target[..<amp]) }
            target = target.removingPercentEncoding ?? target
        }
        return target.replacingOccurrences(of: "#", with: "")
    }

    private static let ignoredCardTemplates: Set<String> = [
        "configCard", "sponsorCard", "sponsorArticleNews", "fabCard",
        "ratingNodeUserEnv", "adCard", "staticsCard",
    ]

    private static let iconCardTemplates: Set<String> = [
        "iconLinkGridCard", "iconMiniScrollCard", "iconListCard", "iconGridCard",
        "iconMiniGridCard", "iconMiniLinkGridCard", "iconLongTitleGridCard",
        "iconButtonGridCard", "iconLargeScrollCard",
    ]

    private static let linkBarTemplates: Set<String> = [
        "selectorLinkCard", "sortSelectCard", "capsuleListCard", "colorfulScrollCard",
        "iconTabLinkGridCard", "tabGroupCard", "textLinkListCard", "linkCard",
    ]

    public static func rows(from items: [JSON]) -> [HomeFeedRow] {
        var rows: [HomeFeedRow] = []
        var pendingGoods: [PearGoods] = []
        var pendingLives: [LiveTopic] = []

        func flushGoods() {
            guard !pendingGoods.isEmpty else { return }
            rows.append(.goods("goods-\(rows.count)", pendingGoods))
            pendingGoods = []
        }

        func flushLives() {
            guard !pendingLives.isEmpty else { return }
            rows.append(.lives("lives-\(rows.count)", pendingLives))
            pendingLives = []
        }

        func flushAll() {
            flushGoods()
            flushLives()
        }

        for (index, item) in items.enumerated() {
            let template = item.entityTemplate.string
            switch item.entityType.string {
            case "pear_goods":
                flushLives()
                pendingGoods.append(PearGoods(json: item))
                continue
            case "liveTopic":
                flushGoods()
                pendingLives.append(LiveTopic(json: item))
                continue
            default:
                break
            }

            flushAll()
            if GoodsRankingItem.looksLikeGoodsRankingJSON(item) {
                let ranking = GoodsRankingItem(json: item)
                if !ranking.title.isEmpty || !ranking.products.isEmpty {
                    rows.append(.goodsRanking(ranking))
                    continue
                }
            }
            switch item.entityType.string {
            case "feed", "feed_reply", "reply", "forwardFeed", "feedLike", "like",
                 "rating", "ratingFeed", "feed_rating", "nodeRating", "apkRating", "productRating":
                let payload = Self.mergedFeedPayload(from: item)
                rows.append(.feed(FeedItem(json: payload)))
            case "history", "recentHistory":
                rows.append(.browse(BrowseItem(json: item)))
            case "recentHistoryEntity", "visited", "recentVisit":
                rows.append(.browse(BrowseItem(json: item)))
            case "collection":
                rows.append(.collection(CollectionItem(json: item)))
            case "event", "activity":
                rows.append(.event(EventItem(json: item)))
            case "dyh":
                rows.append(.dyh(DyhItem(json: item)))
            case "product":
                rows.append(.product(ProductItem(json: item)))
            case "topic":
                rows.append(.topic(TopicItem(json: item)))
            case "user":
                rows.append(.user(UserBrief(json: item)))
            case "apk":
                rows.append(.app(AppItem(json: item)))
            case "card":
                rows.append(contentsOf: cardRows(item, template: template, index: index))
            default:
                if item.feedInfo.exists {
                    rows.append(.feed(FeedItem(json: Self.mergedFeedPayload(from: item))))
                } else if Self.looksLikeFeedOrRatingJSON(item) {
                    rows.append(.feed(FeedItem(json: item)))
                } else if !template.isEmpty || !item.entities.array.isEmpty {
                    let mappedCards = cardRows(item, template: template, index: index)
                    if !mappedCards.isEmpty {
                        rows.append(contentsOf: mappedCards)
                    } else if !item.title.string.isEmpty && !item.url.string.isEmpty {
                        rows.append(.linkBar("misc-\(index)", [
                            HomeSection(
                                id: "misc-\(index)-\(item.entityId.identifier)",
                                title: item.title.string,
                                subtitle: item.sub_title.string,
                                url: item.url.string,
                                style: item.logo.string.isEmpty ? item.pic.string : item.logo.string
                            )
                        ]))
                    }
                } else if !item.title.string.isEmpty && !item.url.string.isEmpty {
                    rows.append(.linkBar("misc-\(index)", [
                        HomeSection(
                            id: "misc-\(index)-\(item.entityId.identifier)",
                            title: item.title.string,
                            subtitle: item.sub_title.string,
                            url: item.url.string,
                            style: item.logo.string.isEmpty ? item.pic.string : item.logo.string
                        )
                    ]))
                }
                continue
            }
        }
        flushAll()
        // Merge consecutive .banners rows (e.g. when /v6/main/indexV8 returns multiple top banner cards)
        // so the top carousel displays all banners together in one stacked deck.
        var coalesced: [HomeFeedRow] = []
        for row in rows {
            if case let .banners(key, incoming) = row,
               let lastIdx = coalesced.indices.last,
               case let .banners(prevKey, existing) = coalesced[lastIdx] {
                var combined = existing
                var seenURLs = Set(existing.map(\.image))
                for b in incoming where seenURLs.insert(b.image).inserted {
                    combined.append(b)
                }
                coalesced[lastIdx] = .banners(prevKey.isEmpty ? key : prevKey, combined)
            } else {
                coalesced.append(row)
            }
        }
        // Deduplicate any identical row IDs within the same batch so SwiftUI ForEach never sees duplicate IDs
        // (which causes cards to flicker/disappear or leave blank gaps during scroll in LazyVStack).
        var seenRowIDs = Set<String>()
        var deduplicated: [HomeFeedRow] = []
        deduplicated.reserveCapacity(coalesced.count)
        for (idx, row) in coalesced.enumerated() {
            let rid = row.id
            if seenRowIDs.insert(rid).inserted {
                deduplicated.append(row)
            } else {
                // Re-key structural rows if their ID collided
                switch row {
                case let .sectionTitle(k, t, u, s):
                    deduplicated.append(.sectionTitle(key: "\(k)-dup-\(idx)", title: t, url: u, subtitle: s))
                case let .icons(k, links):
                    deduplicated.append(.icons("\(k)-dup-\(idx)", links))
                case let .sections(k, secs):
                    deduplicated.append(.sections("\(k)-dup-\(idx)", secs))
                case let .banners(k, bans):
                    deduplicated.append(.banners("\(k)-dup-\(idx)", bans))
                default:
                    break
                }
            }
        }
        return deduplicated
    }

    private static func looksLikeFeedOrRatingJSON(_ item: JSON) -> Bool {
        if item.feedInfo.isObject { return true }
        let eType = item.entityType.string.lowercased()
        if eType == "feed" || eType == "feed_reply" || eType == "reply"
            || eType == "rating" || eType == "ratingfeed" || eType == "feed_rating"
            || eType == "noderating" || eType == "apkrating" || eType == "productrating" {
            return true
        }
        let hasUser = !item.uid.identifier.isEmpty || !item.userInfo.uid.identifier.isEmpty || !item.username.string.isEmpty
        guard hasUser else { return false }
        let hasContent = !item.message.string.isEmpty
            || !item.message_title.string.isEmpty
            || item.rating_score.double > 0
            || !item.comment_good.string.isEmpty
            || !item.comment_bad.string.isEmpty
            || !item.comment_general.string.isEmpty
            || item.v4_rating_message.exists
            || !item.tsubdata.string.isEmpty
            || item.tsubdata.isObject
            || !item.picArr.array.isEmpty
            || !item.pic.string.isEmpty
        return hasContent
    }

    private static func mergedFeedPayload(from wrapper: JSON, inner: JSON? = nil) -> JSON {
        let base: JSON
        if let inner {
            base = inner.feedInfo.isObject ? inner.feedInfo : inner
        } else if wrapper.feedInfo.isObject {
            base = wrapper.feedInfo
        } else {
            return wrapper
        }
        guard case var .object(baseDict) = base.value,
              case let .object(wrapDict) = wrapper.value else {
            return base
        }
        for (k, v) in wrapDict {
            if baseDict[k] == nil {
                baseDict[k] = v
            }
        }
        return JSON(value: .object(baseDict))
    }

    private static func cardRows(_ item: JSON, template: String, index: Int) -> [HomeFeedRow] {
        if ignoredCardTemplates.contains(template) { return [] }

        let entities = item.entities.array
        let title = item.title.string
        let moreURL = item.url.string

        func titled(_ rows: [HomeFeedRow]) -> [HomeFeedRow] {
            guard !title.isEmpty else { return rows }
            return [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")] + rows
        }

        if GoodsRankingItem.looksLikeGoodsRankingJSON(item) {
            let ranking = GoodsRankingItem(json: item)
            if !ranking.title.isEmpty || !ranking.products.isEmpty {
                return titled([.goodsRanking(ranking)])
            }
        }

        let goodsRankingEntities = entities.filter { GoodsRankingItem.looksLikeGoodsRankingJSON($0) }
        if !goodsRankingEntities.isEmpty && goodsRankingEntities.count == entities.count {
            let mapped = goodsRankingEntities.map { GoodsRankingItem(json: $0) }.filter { !$0.title.isEmpty || !$0.products.isEmpty }
            if !mapped.isEmpty {
                return titled(mapped.map { .goodsRanking($0) })
            }
        }

        if !entities.isEmpty, entities.allSatisfy({ $0.entityType.string == "pear_goods" }) {
            return titled([.goods("goods-\(index)", entities.map { PearGoods(json: $0) })])
        }

        if template == "eventCard" || template == "activityCard" {
            let events = entities.map { EventItem(json: $0) }.filter { !$0.title.isEmpty || !$0.cover.isEmpty }
            if !events.isEmpty { return titled(events.map { HomeFeedRow.event($0) }) }
        }

        if template == "subTabFeedCard" || template.lowercased().contains("subtabfeed") {
            let feedEntities = entities.filter { Self.looksLikeFeedOrRatingJSON($0) }
            if !feedEntities.isEmpty {
                return titled(feedEntities.map { .feed(FeedItem(json: Self.mergedFeedPayload(from: item, inner: $0))) })
            }
            if Self.looksLikeFeedOrRatingJSON(item) {
                return [.feed(FeedItem(json: Self.mergedFeedPayload(from: item)))]
            }
        }

        if template == "listCard" || template == "productTimelineListCard" {
            let feedEntities = entities.filter { Self.looksLikeFeedOrRatingJSON($0) }
            if !feedEntities.isEmpty && feedEntities.count == entities.count {
                return titled(feedEntities.map { .feed(FeedItem(json: Self.mergedFeedPayload(from: $0))) })
            }
            let eventEntities = entities.filter {
                $0.entityType.string == "event" || $0.url.string.contains("/event/")
            }
            if !eventEntities.isEmpty && eventEntities.count == entities.count {
                return titled(eventEntities.map { HomeFeedRow.event(EventItem(json: $0)) })
            }
            let topicEntities = entities.filter {
                $0.entityType.string == "topic" || $0.entityTemplate.string == "topicCard" || $0.url.string.hasPrefix("/t/")
            }
            if !topicEntities.isEmpty && topicEntities.count == entities.count {
                return titled(topicEntities.map { HomeFeedRow.topic(TopicItem(json: $0)) })
            }
            let apkEntities = entities.filter {
                $0.entityType.string == "apk" || $0.url.string.hasPrefix("/apk/") || $0.url.string.hasPrefix("/game/")
            }
            if !apkEntities.isEmpty && apkEntities.count == entities.count {
                return titled(apkEntities.map { HomeFeedRow.app(AppItem(json: $0)) })
            }
            let dyhEntities = entities.filter {
                $0.entityType.string == "dyh" || $0.url.string.hasPrefix("/dyh/")
            }
            if !dyhEntities.isEmpty && dyhEntities.count == entities.count {
                return titled(dyhEntities.map { HomeFeedRow.dyh(DyhItem(json: $0)) })
            }
            let colEntities = entities.filter {
                $0.entityType.string == "collection" || $0.url.string.hasPrefix("/collection/")
            }
            if !colEntities.isEmpty && colEntities.count == entities.count {
                return titled(colEntities.map { HomeFeedRow.collection(CollectionItem(json: $0)) })
            }
            let productEntities = entities.filter {
                $0.entityType.string == "product" || $0.url.string.hasPrefix("/product/") || $0.price_min.exists
            }
            if !productEntities.isEmpty {
                let products = productEntities.map { ProductItem(json: $0) }
                if let only = products.first, products.count == 1 { return titled([.product(only)]) }
                return titled(products.prefix(8).map { HomeFeedRow.product($0) })
            }
            if entities.count == 1, let only = entities.first {
                if !only.logo.string.isEmpty && (only.follow_num.int > 0 || only.follownum.int > 0 || only.commentnum.int > 0 || only.feed_num.int > 0) {
                    if only.url.string.contains("/product/") || only.entityType.string == "product" {
                        return titled([.product(ProductItem(json: only))])
                    }
                    return titled([.topic(TopicItem(json: only))])
                }
            }
        }

        if template == "iconButtonGridCard" {
            let banners = entities.enumerated().compactMap { offset, entity -> HomeBanner? in
                let image = entity.pic.string
                guard !image.isEmpty else { return nil }
                return HomeBanner(
                    id: "bgrid-\(index)-\(offset)-\(entity.entityId.identifier)",
                    title: entity.title.string,
                    subtitle: "",
                    image: image,
                    url: entity.url.string
                )
            }
            if !banners.isEmpty { return [.banners("banner-\(index)", banners)] }
        }

        let isCarouselOrImageTemplate = template.lowercased().contains("carousel")
            || template == "imageSquareScrollCard"
            || template == "imageTextScrollCard"
            || template == "imageCard"
            || template == "imageScaleCard"
            || template == "singleImageCard"
        if !isCarouselOrImageTemplate,
           !entities.isEmpty,
           entities.allSatisfy({ $0.entityType.string == "event" }) {
            let events = entities.map { EventItem(json: $0) }.filter { !$0.title.isEmpty || !$0.cover.isEmpty }
            if !events.isEmpty { return titled(events.map { HomeFeedRow.event($0) }) }
        }

        if iconCardTemplates.contains(template) {
            if entities.count == 1, let only = entities.first {
                let eType = only.entityType.string.lowercased()
                let eUrl = only.url.string
                if eType == "topic" || only.entityTemplate.string == "topicCard" || eUrl.hasPrefix("/t/") {
                    let topic = TopicItem(json: only)
                    if !topic.title.isEmpty && (!topic.logo.isEmpty || topic.followNum > 0 || topic.feedNum > 0) {
                        return titled([.topic(topic)])
                    }
                } else if eType == "product" || eUrl.hasPrefix("/product/") {
                    let prod = ProductItem(json: only)
                    if !prod.title.isEmpty && !prod.logo.isEmpty {
                        return titled([.product(prod)])
                    }
                } else if eType == "apk" || eUrl.hasPrefix("/apk/") || eUrl.hasPrefix("/game/") {
                    let app = AppItem(json: only)
                    if !app.title.isEmpty && !app.logo.isEmpty {
                        return titled([.app(app)])
                    }
                } else if eType == "dyh" || eUrl.hasPrefix("/dyh/") {
                    let dyh = DyhItem(json: only)
                    if !dyh.title.isEmpty && !dyh.logo.isEmpty {
                        return titled([.dyh(dyh)])
                    }
                } else if eType == "collection" || eUrl.hasPrefix("/collection/") {
                    let col = CollectionItem(json: only)
                    if !col.title.isEmpty {
                        return titled([.collection(col)])
                    }
                }
            }
            var links = entities.enumerated().map { offset, entity in
                iconLink(from: entity, parentCard: item, keyPrefix: "icon-\(index)-\(offset)", offset: offset)
            }.filter { !$0.image.isEmpty || !$0.title.isEmpty }
            if links.isEmpty && (!item.pic.string.isEmpty || !item.logo.string.isEmpty) {
                links = [iconLink(from: item, parentCard: .null, keyPrefix: "icon-self-\(index)")]
            }
            if links.isEmpty { return [] }
            if links.allSatisfy({ $0.image.isEmpty }) {
                let sections = links.map { HomeSection(id: $0.id, title: $0.title, subtitle: $0.subtitle, url: $0.url, style: "") }
                return titled([.linkList("linklist-\(index)", sections)])
            }
            return titled([.icons("icons-\(index)", links)])
        }

        if linkBarTemplates.contains(template) {
            let selectedTitle = item.extraDataArr.selectedTab.string.isEmpty
                ? item.extraData.parsed.selectedTab.string
                : item.extraDataArr.selectedTab.string
            let links = entities.enumerated()
                .map { offset, entity in
                    let resolvedURL = resolveSectionURL(for: entity, parentCard: item, isLinkBar: true)
                    return HomeSection(
                        id: "lbar-\(index)-\(offset)-\(entity.entityId.identifier)-\(entity.title.string)",
                        title: entity.title.string,
                        subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string,
                        url: resolvedURL,
                        style: entity.pic.string
                    )
                }
                .filter { !$0.title.isEmpty }
            if links.isEmpty { return [] }
            if template == "sortSelectCard" || title == "排序规则" {
                let rowKey = "sortbar-\(index)-\(selectedTitle)"
                return [.linkBar(rowKey, links)]
            }
            return titled([.linkBar("linkbar-\(index)", links)])
        }

        switch template {
        case "imageCarouselCard_1", "imageCarouselCard_2", "imageCarouselCard":
            var banners = entities.enumerated().compactMap { offset, entity -> HomeBanner? in
                let image = [
                    entity.pic.string,
                    entity.logo.string,
                    entity.cover.string,
                    entity.picArr.array.first?.string ?? "",
                    entity.extraDataArr.pic.string,
                    entity.extraData.parsed.pic.string
                ].first { !$0.isEmpty } ?? ""
                guard !image.isEmpty else { return nil }
                return HomeBanner(
                    id: "car-\(index)-\(offset)-\(entity.entityId.identifier)-\(image.hashValue)",
                    title: entity.title.string.isEmpty ? entity.description.string : entity.title.string,
                    subtitle: entity.sub_title.string,
                    image: coolapkNormalizedURL(image),
                    url: resolveSectionURL(for: entity, parentCard: item, isLinkBar: false)
                )
            }
            if banners.isEmpty {
                let picArr = item.picArr.array.isEmpty ? item.pics.array : item.picArr.array
                if !picArr.isEmpty {
                    banners = picArr.enumerated().compactMap { offset, picJSON -> HomeBanner? in
                        let rawPic = picJSON.string.isEmpty ? picJSON.url.string : picJSON.string
                        guard !rawPic.isEmpty else { return nil }
                        return HomeBanner(
                            id: "car-picarr-\(index)-\(offset)",
                            title: item.title.string.isEmpty ? item.description.string : item.title.string,
                            subtitle: item.sub_title.string,
                            image: coolapkNormalizedURL(rawPic),
                            url: resolveSectionURL(for: item, parentCard: .null, isLinkBar: false)
                        )
                    }
                }
            }
            if banners.isEmpty {
                let selfImg = [item.pic.string, item.logo.string, item.cover.string].first { !$0.isEmpty } ?? ""
                if !selfImg.isEmpty {
                    banners = [
                        HomeBanner(
                            id: "car-self-\(index)-\(selfImg.hashValue)",
                            title: item.title.string.isEmpty ? item.description.string : item.title.string,
                            subtitle: item.sub_title.string,
                            image: coolapkNormalizedURL(selfImg),
                            url: resolveSectionURL(for: item, parentCard: .null, isLinkBar: false)
                        )
                    ]
                }
            }
            return banners.isEmpty ? [] : [.banners("banner-\(index)-\(banners.first?.id ?? "")", banners)]

        case "imageTextScrollCard":
            let sections = entities.enumerated().map { offset, entity in
                HomeSection(
                    id: "sec-\(index)-\(offset)-\(entity.entityId.identifier)-\(entity.title.string)",
                    title: entity.title.string,
                    subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string,
                    url: resolveSectionURL(for: entity, parentCard: item, isLinkBar: true),
                    style: coolapkNormalizedURL(!entity.pic.string.isEmpty ? entity.pic.string : entity.logo.string)
                )
            }.filter { !$0.style.isEmpty || !$0.title.isEmpty }
            return sections.isEmpty ? [] : titled([.sections("sections-\(index)", sections)])

        case "verticalColumnsFullPageCard":
            let columns = entities.enumerated()
                .map { offset, entity in
                    HomeSection(
                        id: "col-\(index)-\(offset)-\(entity.entityId.identifier)-\(entity.title.string)",
                        title: entity.title.string,
                        subtitle: entity.sub_title.string,
                        url: resolveSectionURL(for: entity, parentCard: item, isLinkBar: true),
                        style: entity.pic.string
                    )
                }
                .filter { !$0.title.isEmpty }
            return columns.isEmpty ? [] : [.columnTabs("columns-\(index)", columns)]

        case "titleCard":
            return title.isEmpty ? [] : [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")]

        case "unLoginCard":
            return [.loginPrompt("\(index)", title.isEmpty ? "更多精彩内容请登录" : title)]

        case "messageCard":
            let text = item.description.string
            return text.isEmpty ? [] : [.notice("\(index)", text)]

        case "feedListCard":
            let feedRows = entities
                .filter { Self.looksLikeFeedOrRatingJSON($0) }
                .map { HomeFeedRow.feed(FeedItem(json: Self.mergedFeedPayload(from: $0))) }
            if !feedRows.isEmpty {
                return titled(feedRows)
            }
            return title.isEmpty ? [] : [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")]

        case "imageCard", "imageScaleCard", "singleImageCard", "imageSquareScrollCard", "imageTextGridCard":
            var sections = entities.enumerated().map { offset, entity in
                HomeSection(
                    id: "imgsec-\(index)-\(offset)-\(entity.entityId.identifier)",
                    title: entity.title.string,
                    subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string,
                    url: resolveSectionURL(for: entity, parentCard: item, isLinkBar: false),
                    style: !entity.pic.string.isEmpty ? entity.pic.string : entity.logo.string
                )
            }.filter { !$0.style.isEmpty || !$0.title.isEmpty }
            if sections.isEmpty && (!item.pic.string.isEmpty || !item.logo.string.isEmpty) {
                sections = [
                    HomeSection(
                        id: "imgsec-self-\(index)",
                        title: item.title.string,
                        subtitle: item.sub_title.string.isEmpty ? item.description.string : item.sub_title.string,
                        url: resolveSectionURL(for: item, parentCard: .null, isLinkBar: false),
                        style: !item.pic.string.isEmpty ? item.pic.string : item.logo.string
                    )
                ]
            }
            return sections.isEmpty ? [] : [.sections("sections-\(index)", sections)]

        default:
            if entities.count == 1, let only = entities.first {
                let eType = only.entityType.string.lowercased()
                let eUrl = only.url.string
                if eType == "topic" || only.entityTemplate.string == "topicCard" || eUrl.hasPrefix("/t/") {
                    let topic = TopicItem(json: only)
                    if !topic.title.isEmpty && (!topic.logo.isEmpty || topic.followNum > 0 || topic.feedNum > 0) {
                        return titled([.topic(topic)])
                    }
                } else if eType == "product" || eUrl.hasPrefix("/product/") {
                    let prod = ProductItem(json: only)
                    if !prod.title.isEmpty && !prod.logo.isEmpty {
                        return titled([.product(prod)])
                    }
                } else if eType == "apk" || eUrl.hasPrefix("/apk/") || eUrl.hasPrefix("/game/") {
                    let app = AppItem(json: only)
                    if !app.title.isEmpty && !app.logo.isEmpty {
                        return titled([.app(app)])
                    }
                } else if eType == "dyh" || eUrl.hasPrefix("/dyh/") {
                    let dyh = DyhItem(json: only)
                    if !dyh.title.isEmpty && !dyh.logo.isEmpty {
                        return titled([.dyh(dyh)])
                    }
                } else if eType == "collection" || eUrl.hasPrefix("/collection/") {
                    let col = CollectionItem(json: only)
                    if !col.title.isEmpty {
                        return titled([.collection(col)])
                    }
                }
            }
            var links = entities.enumerated().map { offset, entity in
                iconLink(from: entity, parentCard: item, keyPrefix: "def-\(index)-\(offset)", offset: offset)
            }.filter { !$0.image.isEmpty || !$0.title.isEmpty }
            if links.isEmpty && (!item.pic.string.isEmpty || !item.logo.string.isEmpty) {
                links = [iconLink(from: item, parentCard: .null, keyPrefix: "def-self-\(index)")]
            }
            if !links.isEmpty {
                if links.allSatisfy({ $0.image.isEmpty }) {
                    let sections = links.map { HomeSection(id: $0.id, title: $0.title, subtitle: $0.subtitle, url: $0.url, style: "") }
                    return titled([.linkList("linklist-\(index)", sections)])
                }
                return titled([.icons("icons-\(index)", links)])
            }
            if !title.isEmpty, entities.isEmpty {
                if !moreURL.isEmpty {
                    return [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")]
                }
                return [.text("text-\(index)", title)]
            }
        }
        return []
    }

    private static func resolveSectionURL(for entity: JSON, parentCard: JSON = .null, isLinkBar: Bool = true) -> String {
        let title = entity.title.string.trimmingCharacters(in: .whitespacesAndNewlines)

        let directCandidates = [
            entity.url.string,
            entity.extraDataArr.url.string,
            entity.extraData.parsed.url.string,
            entity.target_url.string,
            entity.jump_url.string,
            entity.link.string,
            entity.uri.string
        ]
        for candidate in directCandidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if !trimmed.hasPrefix("/") && !trimmed.hasPrefix("#") && !trimmed.contains("://") && !trimmed.hasPrefix("page?") {
                    return "#/page?url=\(trimmed)&title=\(title)"
                }
                return trimmed
            }
        }

        let pageCandidates = [
            entity.page_name.string,
            entity.pageName.string,
            entity.extraDataArr.page_name.string,
            entity.extraData.parsed.page_name.string
        ]
        for pageName in pageCandidates {
            let trimmed = pageName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return "#/page?url=\(trimmed)&title=\(title)"
            }
        }

        if let firstChild = entity.entities.array.first {
            let childURL = resolveSectionURL(for: firstChild, parentCard: entity, isLinkBar: false)
            if !childURL.isEmpty {
                return childURL
            }
        }

        let eType = entity.entityType.string.lowercased()
        let eTemplate = entity.entityTemplate.string.lowercased()
        let combinedType = "\(eType) \(eTemplate)"
        if combinedType.contains("ershou") || combinedType.contains("secondhand") {
            let isMainSecondHand = combinedType.contains("mainershou") || combinedType.contains("mainsecondhand")
            let brand = [entity.brandId.identifier, entity.brand_id.identifier, entity.brand.string, entity.brandName.string, entity.brand_name.string].first { !$0.isEmpty } ?? ""
            let pid = isMainSecondHand
                ? ([entity.productId.identifier, entity.product_id.identifier].first { !$0.isEmpty && $0 != "0" } ?? "")
                : ([entity.productId.identifier, entity.product_id.identifier, entity.id.identifier, entity.entityId.identifier].first { !$0.isEmpty && $0 != "0" } ?? "")
            let sthType = [
                entity.secondHandSthType.identifier,
                entity.second_hand_sth_type.identifier,
                entity.ershouType.identifier,
                entity.ershou_type.identifier,
                entity.secondHandType.identifier,
                entity.second_hand_type.identifier,
                isMainSecondHand ? entity.id.identifier : "100"
            ].first { !$0.isEmpty } ?? ""
            if !pid.isEmpty || !sthType.isEmpty {
                let city = [entity.cityId.identifier, entity.city_id.identifier].first { !$0.isEmpty } ?? ""
                let listType = [entity.dataListType.string, entity.data_list_type.string].first { !$0.isEmpty } ?? "staggered"
                return "/feed/ershouList?brand=\(brand)&productId=\(pid)&cityId=\(city)&ershouType=\(sthType)&dataListType=\(listType)"
            }
        }
        let rawID = [entity.id.identifier, entity.entityId.identifier].first { !$0.isEmpty && $0 != "0" } ?? ""
        switch eType {
        case "topic", "topictag", "tag":
            let cleanTag = TopicItem.cleanTitle(title)
            if !cleanTag.isEmpty { return "/t/\(cleanTag)" }
        case "product":
            if !rawID.isEmpty { return "/product/\(rawID)" }
        case "apk", "app", "game":
            let apkTarget = !entity.apkname.string.isEmpty ? entity.apkname.string : rawID
            if !apkTarget.isEmpty { return "/apk/\(apkTarget)" }
        case "dyh":
            let dyhTarget = !entity.dyh_id.identifier.isEmpty ? entity.dyh_id.identifier : rawID
            if !dyhTarget.isEmpty { return "/dyh/\(dyhTarget)" }
        case "collection":
            if !rawID.isEmpty { return "/collection/\(rawID)" }
        case "user", "contacts":
            let uidTarget = !entity.uid.identifier.isEmpty ? entity.uid.identifier : rawID
            if !uidTarget.isEmpty { return "/u/\(uidTarget)" }
        case "feed", "feed_reply", "reply":
            if !rawID.isEmpty { return "/feed/\(rawID)" }
        case "event", "activity":
            if !rawID.isEmpty { return "/event/\(rawID)" }
        default:
            break
        }

        let parentURL = parentCard.url.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !parentURL.isEmpty {
            let sep = parentURL.contains("?") ? "&" : "?"
            return title.isEmpty ? parentURL : "\(parentURL)\(sep)title=\(title)"
        }

        if isLinkBar && !title.isEmpty {
            let cleanTag = TopicItem.cleanTitle(title)
            if !cleanTag.isEmpty {
                return "/t/\(cleanTag)"
            }
        }
        return ""
    }

    private static func iconLink(from entity: JSON, parentCard: JSON = .null, keyPrefix: String = "icon", offset: Int = -1) -> HomeIconLink {
        let title = entity.title.string.isEmpty ? entity.username.string : entity.title.string
        let image = !entity.logo.string.isEmpty
            ? entity.logo.string
            : (!entity.pic.string.isEmpty ? entity.pic.string : entity.userAvatar.string)
        let resolvedURL = resolveSectionURL(for: entity, parentCard: parentCard, isLinkBar: image.isEmpty)
        let withRanking = parentCard.extraDataArr.withRanking.int == 1
            || parentCard.extraData.parsed.withRanking.int == 1
            || parentCard.extraDataArr.withRanking.bool
            || parentCard.extraData.parsed.withRanking.bool
        let hotText = [
            entity.hot_num_txt.string,
            entity.hotNumTxt.string,
            withRanking ? entity.sub_title.string : ""
        ].first { !$0.isEmpty } ?? ""
        let subtitle = withRanking ? "" : (entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string)
        let rank = (withRanking && offset >= 0) ? (offset + 1) : 0
        return HomeIconLink(
            id: "\(keyPrefix)-\(entity.entityId.identifier)-\(title)",
            title: title,
            image: coolapkNormalizedURL(image),
            url: resolvedURL,
            subtitle: subtitle,
            hotText: hotText,
            rank: rank
        )
    }

    // MARK: - Feed Detail & Replies

    public static func feedDetail(id: String, allowPublicFallback: Bool = true) async throws -> FeedItem {
        do {
            let json = try await client.get("/v6/feed/detail", ["id": id, "withSubTabFeedCard": "1"], clearProofOnCaptcha: !allowPublicFallback)
            let data = json.data
            let entityType = data.entityType.string.lowercased()
            let parentFID = [data.fid.identifier, data.feed_id.identifier, data.feedId.identifier]
                .first { !$0.isEmpty && $0 != "0" && $0 != id }
            if (entityType == "feed_reply" || entityType == "reply"),
               let parentFID,
               let parentJSON = try? await client.get("/v6/feed/detail", ["id": parentFID, "withSubTabFeedCard": "1"], clearProofOnCaptcha: false),
               parentJSON.data.isObject,
               !parentJSON.data.id.identifier.isEmpty {
                var parentItem = FeedItem(json: parentJSON.data)
                await enrichSubTabPriceIfNeeded(&parentItem, rawJSON: parentJSON.data)
                return parentItem
            }
            var item = FeedItem(json: data)
            await enrichSubTabPriceIfNeeded(&item, rawJSON: data)
            return item
        } catch let error as APIError {
            // If `id` came from a notification reply link (`feed_reply` ID rather than top-level `feed` ID),
            // `/v6/feed/detail` returns "无法访问该数据". Probe replyDetail / replyList to resolve the parent `fid`.
            if let resolvedFromReply = await resolveFeedFromReplyIDIfPossible(replyID: id, allowPublicFallback: allowPublicFallback) {
                return resolvedFromReply
            }
            if allowPublicFallback {
                if let pub = try? await client.publicFeedJSON(id: id) {
                    return FeedItem(json: pub.data)
                }
            }
            throw error
        }
    }

    /// When a product subtab post (such as a "数码产品 → 到手价" post like 75284108) is opened directly by ID,
    /// if `/v6/feed/detail` omitted the subTabFeedCard payload that `/v6/page/dataList` (`withSubTabFeedCard=1`, `subId=6`) includes,
    /// probe the product's `subId=6` subtab feed list to enrich `priceText` and `dealStatusText`.
    private static func enrichSubTabPriceIfNeeded(_ item: inout FeedItem, rawJSON: JSON) async {
        guard item.priceText.isEmpty else { return }
        var candidateProductID = ""
        if rawJSON.targetRow.targetType.string.lowercased() == "product" || rawJSON.targetRow.entityType.string.lowercased() == "product" || rawJSON.targetRow.url.string.contains("/product/") {
            candidateProductID = rawJSON.targetRow.id.identifier
        }
        if candidateProductID.isEmpty {
            for rel in item.relationEntities {
                if let range = rel.url.range(of: "/product/") {
                    let tail = String(rel.url[range.upperBound...])
                    let pid = tail.split(whereSeparator: { !$0.isNumber }).first.map(String.init) ?? ""
                    if !pid.isEmpty {
                        candidateProductID = pid
                        break
                    }
                }
            }
        }
        guard !candidateProductID.isEmpty, candidateProductID != "0" else { return }
        let extra: [String: String] = [
            "cacheExpires": "60",
            "type": "subTabFeed",
            "withSortCard": "1",
            "withSubTabFeedCard": "1",
            "ignoreEntityById": "1",
            "id": candidateProductID,
            "subId": "6"
        ]
        for page in 1...2 {
            guard let listItems = try? await client.dataList(
                url: "/page?url=/product/feedList",
                page: page,
                extra: extra
            ), !listItems.isEmpty else { break }
            for row in rows(from: listItems) {
                if case let .feed(candidate) = row,
                   (candidate.id == item.id || candidate.effectiveFeedID == item.id),
                   !candidate.priceText.isEmpty {
                    item.mergePreservedMetadata(from: candidate)
                    return
                }
            }
        }
    }

    private static func resolveFeedFromReplyIDIfPossible(replyID: String, allowPublicFallback: Bool) async -> FeedItem? {
        guard !replyID.isEmpty, replyID != "0" else { return nil }
        let candidateEndpoints: [(String, [String: String])] = [
            ("/v6/feed/replyDetail", ["id": replyID]),
            ("/v6/feed/detail", ["id": replyID, "type": "feed_reply"]),
            ("/v6/feed/replyList", [
                "id": replyID,
                "page": "1",
                "discussMode": "0",
                "feedType": "feed_reply",
                "blockStatus": "0",
                "fromFeedAuthor": "0"
            ])
        ]
        var fallbackReplyJSON: JSON?
        for (path, query) in candidateEndpoints {
            guard let json = try? await client.get(path, query, clearProofOnCaptcha: false) else { continue }
            let data = json.data
            let objects: [JSON] = data.isObject ? [data, data.feedInfo, data.targetRow] : data.array
            for obj in objects where obj.isObject {
                let parentFID = [
                    obj.fid.identifier,
                    obj.feed_id.identifier,
                    obj.feedId.identifier,
                    obj.feedInfo.id.identifier,
                    obj.targetRow.id.identifier
                ].first { !$0.isEmpty && $0 != "0" && $0 != replyID }
                if let parentFID {
                    if let parentDetail = try? await client.get("/v6/feed/detail", ["id": parentFID], clearProofOnCaptcha: false),
                       parentDetail.data.isObject,
                       !parentDetail.data.id.identifier.isEmpty {
                        return FeedItem(json: parentDetail.data)
                    }
                    if allowPublicFallback,
                       let pub = try? await client.publicFeedJSON(id: parentFID) {
                        return FeedItem(json: pub.data)
                    }
                }
                if fallbackReplyJSON == nil, !obj.message.string.isEmpty, !obj.uid.identifier.isEmpty {
                    fallbackReplyJSON = obj
                }
            }
        }
        if let fallbackReplyJSON {
            return FeedItem(json: fallbackReplyJSON)
        }
        return nil
    }

    public static func replies(
        feedID: String,
        page: Int,
        listType: String = "lastupdate_desc",
        authorOnly: Bool = false
    ) async throws -> [ReplyItem] {
        let query: [String: String] = [
            "id": feedID,
            "listType": listType,
            "page": String(page),
            "discussMode": "1",
            "feedType": "feed",
            "blockStatus": "0",
            "fromFeedAuthor": authorOnly ? "1" : "0",
        ]
        do {
            // Prefer api2Base first to share host/session state with home timeline, then fall back to apiBase without prematurely wiping proof.
            let json = try await client.get(
                "/v6/feed/replyList",
                query,
                base: CoolapkClient.api2Base,
                clearProofOnCaptcha: false
            )
            return json.data.array
                .filter { ReplyItem.isValidReplyJSON($0) }
                .map { ReplyItem(json: $0) }
        } catch let error as APIError {
            if case .captchaRequired = error {
                let fallbackJSON = try await client.get(
                    "/v6/feed/replyList",
                    query,
                    base: CoolapkClient.apiBase,
                    clearProofOnCaptcha: true
                )
                return fallbackJSON.data.array
                    .filter { ReplyItem.isValidReplyJSON($0) }
                    .map { ReplyItem(json: $0) }
            }
            throw error
        }
    }

    public static func hotReplies(feedID: String, page: Int = 1) async throws -> [ReplyItem] {
        try await replies(feedID: feedID, page: page, listType: "popular")
    }

    public static func subReplies(replyID: String, page: Int) async throws -> [ReplyItem] {
        let json = try await client.get("/v6/feed/replyList", [
            "id": replyID,
            "page": String(page),
            "discussMode": "0",
            "feedType": "feed_reply",
            "blockStatus": "0",
            "fromFeedAuthor": "0",
        ])
        return json.data.array
            .filter { ReplyItem.isValidReplyJSON($0) }
            .map { ReplyItem(json: $0) }
    }

    public static func pinReply(feedID: String, replyID: String?) async throws {
        if let replyID {
            _ = try await client.post("/v6/feed/addReplyTopToFeed", [
                "replyId": replyID,
                "feedId": feedID
            ])
        } else {
            _ = try await client.post("/v6/feed/cancelReplyTopFromFeed", [
                "feedId": feedID
            ])
        }
    }

    // MARK: - Interactions & Publishing

    public static func likeFeed(id: String, liked: Bool) async throws {
        let path = liked ? "/v6/feed/like" : "/v6/feed/unlike"
        _ = try await client.post(path, ["trace": ""], query: ["id": id, "detail": "0"])
    }

    public static func likeReply(id: String, liked: Bool) async throws {
        let path = liked ? "/v6/feed/likeReply" : "/v6/feed/unLikeReply"
        _ = try await client.post(path, ["trace": ""], query: ["id": id, "detail": "0"])
    }

    public static func collectFeed(id: String, collected: Bool) async throws {
        let path = collected ? "/v6/feed/favorite" : "/v6/feed/unFavorite"
        _ = try await client.post(path, ["id": id], query: ["id": id])
    }

    public static func postReply(targetID: String, message: String, isReply: Bool = false, pictures: [String] = []) async throws -> String {
        var form: [String: String] = ["message": message]
        if !pictures.isEmpty {
            form["pic"] = pictures.joined(separator: ",")
        }
        let json = try await client.post("/v6/feed/reply", form, query: [
            "id": targetID,
            "type": isReply ? "reply" : "feed"
        ])
        return json.data.string.isEmpty ? json.message.string : json.data.string
    }

    public static func deleteReply(id: String) async throws {
        _ = try await client.post("/v6/feed/deleteReply", ["id": id])
    }

    public static func deleteFeed(id: String) async throws {
        _ = try await client.post("/v6/feed/delete", ["id": id])
    }

    public static func followUser(uid: String, follow: Bool) async throws {
        _ = try await client.post(
            follow ? "/v6/user/follow" : "/v6/user/unfollow",
            ["uid": uid],
            query: ["uid": uid]
        )
    }

    public static func followTopic(tag: String, follow: Bool) async throws {
        let cleanTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTag.isEmpty else {
            throw APIError.message("话题标签不能为空")
        }
        let path = follow ? "/v6/feed/followTag" : "/v6/feed/unFollowTag"
        _ = try await client.get(path, ["tag": cleanTag])
    }

    public static func followProduct(id: String, follow: Bool) async throws {
        _ = try await client.post("/v6/product/changeFollowStatus", ["id": id, "status": follow ? "1" : "0"])
    }

    public static func uploadImage(data: Data, filename: String) async throws -> String {
        let json = try await client.upload(
            path: "/v6/feed/uploadImage?fieldName=picFile&uploadDir=feed",
            fieldName: "picFile",
            filename: filename,
            data: data
        )
        let link = json.data.string
        guard !link.isEmpty else {
            throw APIError.message(json.message.string.isEmpty ? "图片上传失败" : json.message.string)
        }
        return link
    }

    public static func createFeed(
        message: String,
        pictures: [String],
        publishStatus: String = "0",
        subTabID: String = "",
        subTabData: String = ""
    ) async throws {
        var form: [String: String] = [
            "message": message,
            "type": "feed",
            "is_html_article": "0",
            "status": "1",
            "publish_status": publishStatus
        ]
        if !pictures.isEmpty {
            form["pics"] = pictures.joined(separator: ",")
            form["picArr"] = pictures.joined(separator: ",")
        }
        if !subTabID.isEmpty, !subTabData.isEmpty {
            form["tsubid"] = subTabID
            form["tsubdata"] = subTabData
        }
        _ = try await client.post("/v6/feed/createFeed", form)
    }

    public static func forwardFeed(id: String, message: String) async throws {
        let form: [String: String] = [
            "message": message.isEmpty ? "转发动态" : message,
            "type": "feed",
            "forwardid": id,
            "is_html_article": "0",
            "status": "1",
            "publish_status": "0"
        ]
        _ = try await client.post("/v6/feed/createFeed", form)
    }

    // MARK: - Users

    public static func userProfile(uid: String) async throws -> UserProfile {
        let cleanUID = (uid.removingPercentEncoding ?? uid).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let json = try await client.get("/v6/user/profile", ["uid": cleanUID])
            var parsed = UserProfile(json: json.data)
            if !parsed.id.isEmpty || !parsed.username.isEmpty {
                if parsed.homeTabCards.isEmpty,
                   let spaceJSON = try? await client.get("/v6/user/space", ["uid": cleanUID], clearProofOnCaptcha: false) {
                    let spaceProfile = UserProfile(json: spaceJSON.data)
                    if !spaceProfile.homeTabCards.isEmpty {
                        parsed.homeTabCards = spaceProfile.homeTabCards
                    }
                    if parsed.astro.isEmpty { parsed.astro = spaceProfile.astro }
                    if parsed.ipLocation.isEmpty { parsed.ipLocation = spaceProfile.ipLocation }
                    if parsed.productOwnerCount == 0 { parsed.productOwnerCount = spaceProfile.productOwnerCount }
                }
                return parsed
            }
        } catch let error as APIError {
            if case .captchaRequired = error { throw error }
            // Fall through to /v6/user/space and user feedList fallback when /v6/user/profile returns "无法访问该数据"
        }
        if let spaceJSON = try? await client.get("/v6/user/space", ["uid": cleanUID], clearProofOnCaptcha: false) {
            let parsed = UserProfile(json: spaceJSON.data)
            if !parsed.id.isEmpty || !parsed.username.isEmpty {
                return parsed
            }
        }
        if let feedJSON = try? await client.get("/v6/user/feedList", ["uid": cleanUID, "page": "1", "isIncludeTop": "1"], clearProofOnCaptcha: false),
           let first = feedJSON.data.array.first {
            let userObj = first.userInfo.isObject ? first.userInfo : first
            let parsed = UserProfile(json: userObj)
            if !parsed.id.isEmpty || !parsed.username.isEmpty {
                return parsed
            }
        }
        let json = try await client.get("/v6/user/space", ["uid": cleanUID])
        return UserProfile(json: json.data)
    }

    public static func userSpace(uid: String) async throws -> UserProfile {
        let json = try await client.get("/v6/user/space", ["uid": uid])
        return UserProfile(json: json.data)
    }

    public static func userFeeds(uid: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/feedList", ["uid": uid, "page": String(page), "isIncludeTop": "1"])
        return rows(from: json.data.array)
    }

    public static func userTabFeeds(uid: String, tabKey: String, page: Int) async throws -> [HomeFeedRow] {
        switch tabKey {
        case "feeds":
            return try await userFeeds(uid: uid, page: page)
        case "htmlFeeds":
            let json = try await client.get("/v6/user/htmlFeedList", ["uid": uid, "page": String(page)])
            return rows(from: json.data.array)
        case "qa":
            let json = try await client.get("/v6/user/questionAndAnswerList", ["uid": uid, "page": String(page)])
            return rows(from: json.data.array)
        case "coolpic":
            return try await linkFeed(link: "#/feed/userCoolPictureFeedList?uid=\(uid)", page: page)
        case "ratings":
            return try await linkFeed(link: "/feed/nodeRatingList?uid=\(uid)&targetType=all&parseRatingToFeed=1", page: page)
        case "ershou":
            return try await linkFeed(link: "#/feed/userErshouList?uid=\(uid)", page: page)
        case "likes":
            return try await userLikeFeeds(uid: uid, page: page)
        default:
            return try await userFeeds(uid: uid, page: page)
        }
    }

    public static func userList(uid: String, followers: Bool, page: Int) async throws -> [UserBrief] {
        let path = followers ? "/v6/user/fansList" : "/v6/user/followList"
        let json = try await client.get(path, ["uid": uid, "page": String(page)])
        return json.data.array.map { item in
            let user = item.userInfo.exists ? item.userInfo : item.fUserInfo
            return UserBrief(json: user.exists ? user : item)
        }
    }

    public static func followedTopics(uid: String? = nil, page: Int = 1) async throws -> [TopicItem] {
        var parameters = ["page": String(page)]
        var target = uid ?? ""
        if target.isEmpty { target = await client.sessionSnapshot().uid }
        if !target.isEmpty { parameters["uid"] = target }
        let json = try await client.get("/v6/user/followTagList", parameters)
        return json.data.array.map { TopicItem(json: $0) }
    }

    public struct LoginCheckResult: Sendable {
        public let isValid: Bool
        public let explicitlyInvalid: Bool
        public let uid: String
        public let username: String
        public let token: String

        public init(
            isValid: Bool,
            explicitlyInvalid: Bool = false,
            uid: String = "",
            username: String = "",
            token: String = ""
        ) {
            self.isValid = isValid
            self.explicitlyInvalid = explicitlyInvalid
            self.uid = uid
            self.username = username
            self.token = token
        }
    }

    public static func checkLoginInfo(expectedUID: String? = nil) async throws -> LoginCheckResult {
        let json = try await client.get("/v6/account/checkLoginInfo")
        if json.message.string == "登录信息有误" {
            return LoginCheckResult(isValid: false, explicitlyInvalid: true)
        }
        if json.data.isObject {
            let uid = json.data.uid.identifier
            let token = json.data.token.string
            let rawName = json.data.username.string
            let username = rawName.removingPercentEncoding ?? rawName
            if let expectedUID, !expectedUID.isEmpty, !uid.isEmpty, uid != expectedUID {
                return LoginCheckResult(isValid: false, explicitlyInvalid: true)
            }
            if !token.isEmpty || !uid.isEmpty {
                return LoginCheckResult(isValid: true, uid: uid, username: username, token: token)
            }
        }
        if json.data.string == "1" || json.data.int == 1 || json.status.int == 1 {
            return LoginCheckResult(isValid: true)
        }
        return LoginCheckResult(isValid: false, explicitlyInvalid: false)
    }

    public static func checkLogin() async throws -> Bool {
        let result = try await checkLoginInfo()
        return result.isValid && !result.explicitlyInvalid
    }

    public static func resolveLivePhotoVideoURL(imageURL: String) async -> String? {
        guard !imageURL.isEmpty else { return nil }
        return await client.resolveRedirectLocation(
            path: "/v6/livePhoto/showVideo",
            query: ["picUrl": imageURL]
        )
    }

    // MARK: - Search

    public static func search(
        keyword: String,
        type: String,
        feedType: String = "all",
        sort: String = "default",
        page: Int
    ) async throws -> [JSON] {
        var query: [String: String] = [
            "type": type,
            "searchValue": keyword,
            "page": String(page),
            "showAnonymous": "-1",
        ]
        if type == "feed" {
            if !feedType.isEmpty { query["feedType"] = feedType }
            if !sort.isEmpty { query["sort"] = sort }
        }
        let json = try await client.get("/v6/search", query)
        return json.data.array
    }

    public static func suggestWords(keyword: String) async throws -> [String] {
        let json = try await client.get("/v6/search/suggestSearchWordsNew", ["searchValue": keyword, "type": "app"])
        return json.data.array.map(\.title.string).filter { !$0.isEmpty }
    }

    public static func searchTags(keyword: String, page: Int = 1) async throws -> [TopicItem] {
        let json = try await client.get("/v6/feed/searchTag", ["q": keyword, "page": String(page)])
        return json.data.array.map { TopicItem(json: $0) }
    }

    public static func searchUsers(keyword: String, page: Int = 1) async throws -> [UserBrief] {
        let json = try await client.get("/v6/user/search", ["q": keyword, "page": String(page)])
        return json.data.array.map { UserBrief(json: $0) }
    }

    // MARK: - Topics, Products, Apps, Collections, Dyh, Events

    public static func topicFeeds(tag: String, page: Int, listType: String = "lastupdate_desc") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/topic/tagFeedList", [
            "tag": tag,
            "page": String(page),
            "listType": listType,
            "blockStatus": "0",
        ])
        return rows(from: json.data.array)
    }

    public static func topicTabFeeds(
        tag: String,
        topicID: String? = nil,
        tab: HomeSection,
        listType: String = "lastupdate_desc",
        page: Int
    ) async throws -> [HomeFeedRow] {
        let trimmedURL = tab.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty || (tab.title == "讨论" && listType != "lastupdate_desc") {
            return try await topicFeeds(tag: tag, page: page, listType: listType)
        }
        if trimmedURL.hasPrefix("/v6/") {
            var params: [String: String] = ["page": String(page), "tag": tag]
            if let topicID, !topicID.isEmpty { params["id"] = topicID }
            if !listType.isEmpty { params["listType"] = listType }
            let json = try await client.get(trimmedURL, params)
            return rows(from: json.data.array)
        }
        let parsed = parsePageLink(trimmedURL)
        var extra = parsed.extra
        if !tab.title.isEmpty, extra["title"] == nil {
            extra["title"] = tab.title
        }
        if !listType.isEmpty, tab.title == "讨论", extra["listType"] == nil {
            extra["listType"] = listType
        }
        let items = try await client.dataList(url: parsed.url, page: page, extra: extra)
        return rows(from: items)
    }

    public static func topicDetail(tag: String) async throws -> TopicItem {
        do {
            let json = try await client.get("/v6/topic/newTagDetail", ["tag": tag])
            return TopicItem(json: json.data)
        } catch {
            let json = try await client.get("/v6/topic/tagDetail", ["tag": tag])
            return TopicItem(json: json.data)
        }
    }

    public static func productDetail(id: String) async throws -> ProductItem {
        let json = try await client.get("/v6/product/detail", ["id": id])
        return ProductItem(json: json.data)
    }

    public static func appIndex(type: Int, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/apk/index", ["apkType": String(type), "page": String(page)])
        return rows(from: json.data.array)
    }

    public static func appDetail(id: String) async throws -> AppItem {
        let json = try await client.get("/v6/apk/detail", ["id": id, "installed": "1"])
        return AppItem(json: json.data)
    }

    public static func appComments(id: String, page: Int, listType: String = "") async throws -> [HomeFeedRow] {
        let sortQuery: String
        let titleText: String
        switch listType {
        case "dateline_desc":
            sortQuery = "&sort=dateline_desc"
            titleText = "最新发布"
        case "popular", "hot":
            sortQuery = "&sort=popular"
            titleText = "热度排序"
        default:
            sortQuery = ""
            titleText = "最近回复"
        }
        let items = try await client.dataList(
            url: "/feed/apkCommentList?isIncludeTop=1&id=\(id)&subTitle=\(sortQuery)",
            page: page,
            extra: ["title": titleText]
        )
        let parsedRows = rows(from: items)
        return parsedRows.filter { row in
            switch row {
            case .linkBar, .linkList, .columnTabs, .sectionTitle:
                return false
            default:
                return true
            }
        }
    }

    private static func expandListEntities(from items: [JSON]) -> [JSON] {
        let expandableTemplates: Set<String> = [
            "listCard", "iconLinkGridCard", "iconMiniScrollCard",
            "iconMiniGridCard", "iconMiniLinkGridCard", "iconScrollCard",
            "iconGridCard", "iconListCard"
        ]
        var expanded: [JSON] = []
        for item in items {
            let eType = item.entityType.string
            let eTemplate = item.entityTemplate.string
            if (eType == "card" || expandableTemplates.contains(eTemplate)) && !item.entities.array.isEmpty {
                expanded.append(contentsOf: item.entities.array)
            } else {
                expanded.append(item)
                if !item.entities.array.isEmpty && item.title.string.isEmpty && item.message.string.isEmpty {
                    expanded.append(contentsOf: item.entities.array)
                }
            }
        }
        return expanded
    }

    public static func collectionList(uid: String?, feedID: String? = nil, page: Int = 1) async throws -> [CollectionItem] {
        let sessionUID = await client.sessionSnapshot().uid
        let trimmedUID = (uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isCurrentUser = trimmedUID.isEmpty || (!sessionUID.isEmpty && trimmedUID == sessionUID)
        let resolvedUID = trimmedUID.isEmpty ? sessionUID : trimmedUID

        func parseCollections(from rawItems: [JSON]) -> [CollectionItem] {
            let expanded = expandListEntities(from: rawItems)
            var seen = Set<String>()
            var result: [CollectionItem] = []
            for raw in expanded {
                let eType = raw.entityType.string
                if eType == "card" || raw.entityTemplate.string == "iconMiniLinkGridCard" {
                    continue
                }
                let col = CollectionItem(json: raw)
                if !col.id.isEmpty && !col.title.isEmpty && seen.insert(col.id).inserted {
                    result.append(col)
                }
            }
            return result
        }

        func extractDataArray(from json: JSON) -> [JSON] {
            if !json.data.array.isEmpty { return json.data.array }
            if !json.data.entities.array.isEmpty { return json.data.entities.array }
            if !json.data.list.array.isEmpty { return json.data.list.array }
            return []
        }

        // Case 1: Picker mode for adding a specific feed (feedID is provided)
        if let feedID, !feedID.isEmpty {
            var pickerParams: [String: String] = [
                "page": String(page),
                "showDefault": "1",
                "id": feedID,
                "type": "feed"
            ]
            if !resolvedUID.isEmpty {
                pickerParams["uid"] = resolvedUID
            }
            let json = try await client.get("/v6/collection/list", pickerParams)
            return parseCollections(from: extractDataArray(from: json))
        }

        // Case 2: Viewing another user's public collections in UserDetailView
        if !isCurrentUser && !resolvedUID.isEmpty {
            let json = try await client.get("/v6/collection/list", [
                "uid": resolvedUID,
                "page": String(page),
                "showDefault": "0"
            ])
            return parseCollections(from: extractDataArray(from: json))
        }

        // Case 3: Viewing the logged-in user's own collections (FavoritesListView / FollowView / UserDetailView self)
        // Per TG-Twilight/c001apk (ffflist_page.dart line 117 & ffflist_content.dart line 41),
        // FFFListType.COLLECTION calls `/v6/collection/list` with `uid: null` and `showDefault: 0`,
        // while `showDefault: 1` (or with `uid` + `showDefault: 1`) guarantees the default collection is also included
        // even when the user has created multiple custom collections.
        var merged: [CollectionItem] = []
        var seenIDs = Set<String>()
        func appendUnique(_ list: [CollectionItem]) {
            for col in list where seenIDs.insert(col.id).inserted {
                merged.append(col)
            }
        }

        // Primary request matching TG-Twilight/c001apk (`uid` omitted, `showDefault: 0`)
        var primaryError: Error?
        do {
            let json0 = try await client.get("/v6/collection/list", [
                "page": String(page),
                "showDefault": "0"
            ])
            appendUnique(parseCollections(from: extractDataArray(from: json0)))
        } catch {
            primaryError = error
        }

        if page == 1 {
            // Also fetch with showDefault=1 (without uid, and with uid) so the cloud default collection ("默认收藏夹")
            // is always included even when the user has multiple custom collections!
            if let json1 = try? await client.get("/v6/collection/list", [
                "page": "1",
                "showDefault": "1"
            ]) {
                appendUnique(parseCollections(from: extractDataArray(from: json1)))
            }

            if !resolvedUID.isEmpty,
               let jsonUID1 = try? await client.get("/v6/collection/list", [
                   "uid": resolvedUID,
                   "page": "1",
                   "showDefault": "1"
               ]) {
                appendUnique(parseCollections(from: extractDataArray(from: jsonUID1)))
            }

            let hasDefaultCol = merged.contains { $0.title.contains("默认") }
            if !hasDefaultCol && !resolvedUID.isEmpty {
                // Coolapk's add-to-collection query with type=feed & showDefault=1 always exposes the user's default collection
                if let jsonPicker = try? await client.get("/v6/collection/list", [
                    "uid": resolvedUID,
                    "page": "1",
                    "showDefault": "1",
                    "type": "feed"
                ]) {
                    appendUnique(parseCollections(from: extractDataArray(from: jsonPicker)))
                }
            }

            // Sort so "默认收藏夹" appears first among cloud collections, preserving relative order of others
            merged.sort { lhs, rhs in
                let lDefault = lhs.title.contains("默认")
                let rDefault = rhs.title.contains("默认")
                if lDefault != rDefault { return lDefault }
                return false
            }
        }

        if merged.isEmpty, let primaryError {
            throw primaryError
        }
        return merged
    }

    public static func collectFeedToCollection(
        feedID: String,
        addCollectionIDs: [String],
        cancelCollectionIDs: [String] = []
    ) async throws {
        let form: [String: String] = [
            "id": addCollectionIDs.joined(separator: ","),
            "cancelId": cancelCollectionIDs.joined(separator: ","),
            "targetId": feedID,
            "type": "feed"
        ]
        _ = try await client.post("/v6/collection/addItem", form)
    }

    public static func createCollection(
        title: String,
        description: String = "",
        isOpen: Bool = true
    ) async throws -> CollectionItem? {
        let json = try await client.post("/v6/collection/create", [
            "title": title,
            "description": description,
            "isOpen": isOpen ? "1" : "0",
            "is_open": isOpen ? "1" : "0"
        ])
        if json.data.isObject {
            let item = CollectionItem(json: json.data)
            if !item.id.isEmpty { return item }
        }
        return nil
    }

    public static func deleteCollection(id: String) async throws {
        _ = try await client.post("/v6/collection/delete", ["id": id])
    }

    public static func collectionDetail(id: String) async throws -> CollectionItem {
        let json = try await client.get("/v6/collection/detail", ["id": id])
        return CollectionItem(json: json.data)
    }

    public static func collectionItems(id: String, page: Int = 1) async throws -> [HomeFeedRow] {
        // Exactly matches TG-Twilight/c001apk FFFListType.COLLECTION_ITEM -> `/v6/collection/itemList`
        let json = try await client.get("/v6/collection/itemList", [
            "id": id,
            "page": String(page)
        ])
        let rawItems: [JSON]
        if !json.data.array.isEmpty {
            rawItems = expandListEntities(from: json.data.array)
        } else if !json.data.entities.array.isEmpty {
            rawItems = expandListEntities(from: json.data.entities.array)
        } else if !json.data.list.array.isEmpty {
            rawItems = expandListEntities(from: json.data.list.array)
        } else {
            rawItems = []
        }

        let standardRows = rows(from: rawItems)
        if !standardRows.isEmpty {
            return standardRows
        }

        // Fallback if any item in `/v6/collection/itemList` has a non-standard entityType
        var fallbackRows: [HomeFeedRow] = []
        var seen = Set<String>()
        for raw in rawItems {
            let eType = raw.entityType.string
            if eType == "card" && raw.message.string.isEmpty { continue }
            let feed = FeedItem(json: raw)
            if !feed.id.isEmpty && (!feed.message.isEmpty || !feed.title.isEmpty || !feed.messageTitle.isEmpty || !feed.pics.isEmpty) {
                if seen.insert(feed.id).inserted {
                    fallbackRows.append(.feed(feed))
                }
            }
        }
        return fallbackRows
    }

    public static func followedProducts(page: Int = 1) async throws -> [ProductItem] {
        let rawItems = try await client.dataList(
            url: "#/product/followProductList",
            page: page,
            extra: ["title": "我关注的数码吧"]
        )
        let expanded = expandListEntities(from: rawItems)
        var seen = Set<String>()
        var items: [ProductItem] = []
        for raw in expanded {
            let p = ProductItem(json: raw)
            if !p.id.isEmpty && !p.title.isEmpty && seen.insert(p.id).inserted {
                items.append(p)
            }
        }
        return items
    }

    public static func followedApps(uid: String? = nil, page: Int = 1) async throws -> [AppItem] {
        let sessionUID = await client.sessionSnapshot().uid
        let trimmedUID = (uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUID = trimmedUID.isEmpty ? sessionUID : trimmedUID
        var params: [String: String] = ["page": String(page)]
        if !resolvedUID.isEmpty {
            params["uid"] = resolvedUID
        }
        let json = try await client.get("/v6/user/apkFollowList", params)
        let expanded = expandListEntities(from: json.data.array)
        var seen = Set<String>()
        var items: [AppItem] = []
        for raw in expanded {
            let app = AppItem(json: raw)
            if !app.id.isEmpty && !app.title.isEmpty && seen.insert(app.id).inserted {
                items.append(app)
            }
        }
        if items.isEmpty && page == 1 {
            if let fallbackItems = try? await client.dataList(
                url: "#/apk/userFollowList",
                page: page,
                extra: ["title": "我关注的应用"]
            ) {
                for raw in expandListEntities(from: fallbackItems) {
                    let app = AppItem(json: raw)
                    if !app.id.isEmpty && !app.title.isEmpty && seen.insert(app.id).inserted {
                        items.append(app)
                    }
                }
            }
        }
        return items
    }

    public static func followedCollections(uid: String? = nil, page: Int = 1) async throws -> [CollectionItem] {
        let sessionUID = await client.sessionSnapshot().uid
        let trimmedUID = (uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUID = trimmedUID.isEmpty ? sessionUID : trimmedUID

        func parseFollowedCollections(from rawArray: [JSON]) -> [CollectionItem] {
            let expanded = expandListEntities(from: rawArray)
            var seen = Set<String>()
            var result: [CollectionItem] = []
            for raw in expanded {
                let eType = raw.entityType.string.lowercased()
                if eType == "card" || raw.entityTemplate.string == "iconMiniLinkGridCard" {
                    continue
                }
                var col = CollectionItem(json: raw)
                if !col.id.isEmpty && !col.title.isEmpty && seen.insert(col.id).inserted {
                    col.isFollowed = true
                    result.append(col)
                }
            }
            return result
        }

        var items: [CollectionItem] = []

        if let dataListItems = try? await client.dataList(
            url: "#/collection/followList",
            page: page,
            extra: ["title": "我关注的收藏夹"]
        ) {
            items = parseFollowedCollections(from: dataListItems)
        }

        if items.isEmpty,
           let directJSON = try? await client.get("/v6/collection/followList", ["page": String(page)]) {
            let arr = !directJSON.data.array.isEmpty ? directJSON.data.array : directJSON.data.entities.array
            items = parseFollowedCollections(from: arr)
        }

        if items.isEmpty,
           !resolvedUID.isEmpty,
           let userFollowItems = try? await client.dataList(
               url: "#/user/followCollectionList?uid=\(resolvedUID)",
               page: page,
               extra: ["title": "关注的收藏夹"]
           ) {
            items = parseFollowedCollections(from: userFollowItems)
        }

        if items.isEmpty,
           let fallbackJSON = try? await client.get("/v6/user/followCollectionList", [
               "uid": resolvedUID,
               "page": String(page)
           ]) {
            items = parseFollowedCollections(from: fallbackJSON.data.array)
        }

        return items
    }

    public static func followedDyhs(page: Int = 1) async throws -> [DyhItem] {
        var seen = Set<String>()
        var items: [DyhItem] = []

        func isGenuineDyhEntity(_ raw: JSON) -> Bool {
            let eType = raw.entityType.string.lowercased()
            let eTemplate = raw.entityTemplate.string.lowercased()
            if eType == "feed" || eType == "feed_reply" || eType == "dyharticle" || eType == "card" {
                return false
            }
            if eTemplate.contains("card") && !raw.entities.array.isEmpty {
                return false
            }
            let rawURL = raw.url.string.lowercased()
            if rawURL.contains("/feed/") || rawURL.contains("/dyharticle/") || rawURL.contains("dyhfollowlist") {
                return false
            }
            if eType == "dyh" || eTemplate == "dyh" || rawURL.contains("/dyh/") || raw.dyh_id.exists || raw.dyhId.exists {
                return true
            }
            return !raw.logo.string.isEmpty && raw.message.string.isEmpty
        }

        func collectDyhs(from rawArray: [JSON]) {
            for item in rawArray {
                if !item.entities.array.isEmpty {
                    collectDyhs(from: item.entities.array)
                }
                guard isGenuineDyhEntity(item) else { continue }
                let dyh = DyhItem(json: item)
                if !dyh.id.isEmpty && dyh.id != "0" && !dyh.title.isEmpty && seen.insert(dyh.id).inserted {
                    items.append(dyh)
                }
            }
        }

        if let dataListItems = try? await client.dataList(
            url: "/user/dyhFollowList",
            page: page,
            extra: ["title": "我订阅的看看号"]
        ) {
            collectDyhs(from: dataListItems)
        }

        if items.isEmpty,
           let directJSON = try? await client.get("/v6/user/dyhFollowList", ["page": String(page)]) {
            collectDyhs(from: directJSON.data.array)
        }

        if items.isEmpty && page == 1 {
            let subscribeJSON = try await client.get("/v6/user/dyhSubscribe", ["page": "1"])
            collectDyhs(from: subscribeJSON.data.array)
        }

        return items
    }

    public static func followCollection(id: String, follow: Bool) async throws {
        let path = follow ? "/v6/collection/follow" : "/v6/collection/unFollow"
        _ = try await client.post(path, ["id": id], query: ["id": id])
    }

    public static func followApp(id: String, follow: Bool) async throws {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = follow ? "/v6/apk/follow" : "/v6/apk/unFollow"
        do {
            _ = try await client.post(path, ["id": cleanID], query: ["id": cleanID])
        } catch {
            _ = try await client.get(path, ["id": cleanID])
        }
    }

    public static func dyhDetail(id: String) async throws -> DyhItem {
        let json = try await client.get("/v6/dyh/detail", ["dyhId": id])
        var item = DyhItem(json: json.data)
        if item.id.isEmpty {
            item = DyhItem(json: json)
        }
        return item
    }

    public static func dyhArticles(id: String, page: Int, type: String = "all") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/dyhArticle/list", [
            "dyhId": id,
            "type": type,
            "page": String(page),
        ])
        return rows(from: json.data.array)
    }

    public static func followDyh(id: String, follow: Bool) async throws {
        var cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleanID.range(of: "/dyh/") {
            let tail = String(cleanID[range.upperBound...])
            let seg = tail.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "&" }).first.map(String.init) ?? ""
            if !seg.isEmpty { cleanID = seg }
        }
        let path = follow ? "/v6/dyh/follow" : "/v6/dyh/unFollow"
        do {
            _ = try await client.post(
                path,
                ["dyhId": cleanID, "id": cleanID],
                query: ["dyhId": cleanID]
            )
        } catch {
            _ = try await client.get(path, ["dyhId": cleanID])
        }
    }

    public static func eventDetail(id: String) async throws -> EventItem {
        let json = try await client.get("/v6/event/detail", ["id": id])
        return EventItem(json: json.data)
    }

    public static func eventFeeds(id: String, page: Int) async throws -> [HomeFeedRow] {
        let candidates = [
            "#/feed/eventFeedList?id=\(id)",
            "#/event/feedList?id=\(id)"
        ]
        for candidate in candidates {
            let parsed = parsePageLink(candidate)
            if let items = try? await client.dataList(url: parsed.url, page: page, extra: parsed.extra) {
                let mapped = rows(from: items)
                if !mapped.isEmpty { return mapped }
            }
        }
        if let json = try? await client.get("/v6/event/feedList", ["id": id, "page": String(page)]) {
            return rows(from: json.data.array)
        }
        return []
    }

    public static func questionAnswers(id: String, page: Int, sort: String = "default") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/question/answerList", [
            "id": id,
            "sort": sort,
            "page": String(page),
        ])
        return rows(from: json.data.array)
    }

    public static func voteComments(fid: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/vote/commentList", ["fid": fid, "page": String(page)])
        return rows(from: json.data.array)
    }

    public static func deviceFeeds(tag: String, page: Int, listType: String = "lastupdate_desc") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/topic/deviceFeedList", [
            "tag": tag,
            "page": String(page),
            "listType": listType,
            "blockStatus": "0",
        ])
        return rows(from: json.data.array)
    }

    // MARK: - Notifications & Chat Messages

    public static func badge() async throws -> NotificationBadge {
        let json = try await client.get("/v6/notification/checkCount")
        return NotificationBadge(json: json.data)
    }

    public static func notifications(type: String, page: Int) async throws -> [NotificationItem] {
        let candidates: [String]
        switch type {
        case "commentMeList", "commentMe":
            candidates = ["commentMeList", "commentList"]
        case "atMeList", "atMe":
            candidates = ["atMeList", "atList", "atCommentMeList"]
        case "feedLikeList", "feedLike":
            candidates = ["feedLikeList", "likeList"]
        case "contactsFollowList", "contactsFollow":
            candidates = ["contactsFollowList", "followList"]
        default:
            candidates = [type]
        }

        var lastError: Error?
        for endpoint in candidates {
            do {
                let json = try await client.get("/v6/notification/\(endpoint)", ["page": String(page)])
                return json.data.array.map { NotificationItem(json: $0) }
            } catch let error as APIError {
                lastError = error
                if case let .message(msg) = error,
                   msg.lowercased().contains("does not exist") || msg.contains("不存在") {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? APIError.message("暂无通知")
    }

    public static func messageThreads(page: Int) async throws -> [MessageThread] {
        let json = try await client.get("/v6/message/list", ["page": String(page)])
        return json.data.array.map { MessageThread(json: $0) }
    }

    public static func chatMessages(ukey: String, peerUID: String = "", page: Int) async throws -> [ChatMessage] {
        var resolvedUkey = ukey.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetUID = peerUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let startedWithBareUID = !targetUID.isEmpty && (resolvedUkey.isEmpty || resolvedUkey == targetUID)

        if startedWithBareUID, page == 1,
           let threads = try? await messageThreads(page: 1),
           let matched = threads.first(where: { $0.uid == targetUID }),
           !matched.ukey.isEmpty {
            resolvedUkey = matched.ukey
        }

        var queries: [[String: String]] = []
        if !resolvedUkey.isEmpty && resolvedUkey != targetUID {
            queries.append(["ukey": resolvedUkey, "page": String(page)])
        }
        if !targetUID.isEmpty {
            queries.append(["uid": targetUID, "page": String(page)])
            let myUID = await client.sessionSnapshot().uid
            if !myUID.isEmpty,
               let myNum = Int64(myUID),
               let peerNum = Int64(targetUID) {
                let low = min(myNum, peerNum)
                let high = max(myNum, peerNum)
                queries.append(["ukey": "\(low),\(high)", "page": String(page)])
                queries.append(["ukey": "\(low)_\(high)", "page": String(page)])
            }
        }
        if queries.isEmpty && !resolvedUkey.isEmpty {
            queries.append(["ukey": resolvedUkey, "page": String(page)])
        }

        var lastError: Error?
        for query in queries {
            do {
                let json = try await client.get("/v6/message/chat", query)
                return json.data.array.map { ChatMessage(json: $0) }.filter { $0.hasVisibleMessageContent }
            } catch let error as APIError {
                lastError = error
                if case let .message(msg) = error,
                   msg.contains("无法查看") || msg.contains("不存在") || msg.contains("无效") {
                    continue
                }
                throw error
            }
        }

        // Brand-new 1v1 chat started from a user profile before any message exists has no server ukey yet.
        if startedWithBareUID, let err = lastError as? APIError,
           case let .message(msg) = err, msg.contains("无法查看") {
            return []
        }
        if let lastError { throw lastError }
        return []
    }

    public static func sendChatMessage(uid: String, text: String, picturePath: String = "") async throws -> [ChatMessage] {
        let json = try await client.postMultipart("/v6/message/send", fields: [
            "message": text,
            "message_pic": picturePath
        ], query: ["uid": uid])
        let arr = json.data.array
        if !arr.isEmpty {
            return arr.map { ChatMessage(json: $0) }
        }
        if json.data.isObject {
            return [ChatMessage(json: json.data)]
        }
        return []
    }

    public static func deleteChatMessage(ukey: String, id: String) async throws {
        let json = try await client.get("/v6/message/delete", ["ukey": ukey, "id": id])
        let count = json.data.isObject ? json.data.count.string : json.data.string
        if count.isEmpty || count == "0" || count == "false" {
            throw APIError.message("服务端未确认删除结果，请刷新后查看")
        }
    }

    public static func deleteMessageThread(ukey: String) async throws {
        _ = try await client.get("/v6/message/deleteChat", ["ukey": ukey])
    }

    public static func clearNotificationCount(type: String = "") async {
        var params: [String: String] = [:]
        if !type.isEmpty { params["type"] = type }
        _ = try? await client.get("/v6/notification/clearCount", params, clearProofOnCaptcha: false)
    }

    public static func markMessageThreadRead(ukey: String) async {
        guard !ukey.isEmpty else { return }
        _ = try? await client.get("/v6/message/read", ["ukey": ukey], clearProofOnCaptcha: false)
    }

    // MARK: - History & Engagement

    public static func recentHistory(page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/recentHistoryList", ["page": String(page)])
        return rows(from: json.data.array)
    }

    public static func hitHistory(page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/hitHistoryList", ["page": String(page)])
        return rows(from: json.data.array)
    }

    public static func likeList(feedID: String, page: Int) async throws -> [UserBrief] {
        let json = try await client.get("/v6/feed/likeList", [
            "id": feedID,
            "listType": "lastupdate_desc",
            "page": String(page),
        ])
        return json.data.array.map { item in
            item.userInfo.exists ? UserBrief(json: item.userInfo) : UserBrief(json: item)
        }
    }

    public static func forwardList(feedID: String, page: Int, type: String = "feed") async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/feed/forwardList", [
            "id": feedID,
            "type": type,
            "page": String(page),
        ])
        return rows(from: json.data.array)
    }

    public static func changeHistory(feedID: String) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/feed/changeHistoryList", ["id": feedID])
        return rows(from: json.data.array)
    }

    public static func userLikeFeeds(uid: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/user/likeList", ["uid": uid, "page": String(page)])
        return rows(from: json.data.array)
    }

    public static func userRecentVisits(uid: String? = nil, page: Int) async throws -> [HomeFeedRow] {
        var params = ["page": String(page)]
        if let uid, !uid.isEmpty { params["uid"] = uid }
        let json = try await client.get("/v6/user/recentHistoryList", params)
        return rows(from: json.data.array)
    }

    public static func userReplies(uid: String, received: Bool = false, page: Int) async throws -> [HomeFeedRow] {
        let path = received ? "/v6/user/replyToMeList" : "/v6/user/replyList"
        let json = try await client.get(path, ["uid": uid, "page": String(page)])
        return rows(from: json.data.array)
    }

    public static func discoverChannels() async throws -> [HomeSection] {
        let json = try await client.get("/v6/main/init", ["t": String(Int(Date().timeIntervalSince1970))])
        var channels: [HomeSection] = []
        for card in json.data.array {
            for entity in card.entities.array {
                let isDiscover = entity.id.identifier == "20131" || entity.entityId.identifier == "20131" || entity.title.string == "发现"
                if isDiscover && !entity.entities.array.isEmpty {
                    for (idx, sub) in entity.entities.array.enumerated() {
                        let title = sub.title.string
                        let pageName = sub.page_name.string
                        let rawURL = sub.url.string
                        let resolvedURL = !rawURL.isEmpty ? rawURL : (!pageName.isEmpty ? "#/page?url=\(pageName)&title=\(title)" : "")
                        if !title.isEmpty && !resolvedURL.isEmpty {
                            channels.append(HomeSection(
                                id: "disc-\(idx)-\(sub.entityId.identifier)-\(title)",
                                title: title,
                                subtitle: sub.sub_title.string,
                                url: resolvedURL,
                                style: coolapkNormalizedURL(sub.logo.string.isEmpty ? sub.pic.string : sub.logo.string)
                            ))
                        }
                    }
                }
            }
        }
        return channels
    }

    public static func myProfileCards() async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/main/loadConfig", ["t": String(Int(Date().timeIntervalSince1970))])
        return rows(from: json.data.array)
    }

    public static func productCategoryGroups() async throws -> [ProductCategoryGroup] {
        let json = try await client.get("/v6/product/categoryList")
        var groups: [ProductCategoryGroup] = []
        for (idx, item) in json.data.array.enumerated() {
            let groupTitle = item.title.string
            guard !groupTitle.isEmpty else { continue }
            let groupLogo = coolapkNormalizedURL(item.logo.string.isEmpty ? item.pic.string : item.logo.string)
            var links: [HomeIconLink] = []

            let secondRows = item.secondCategoryRows.array.isEmpty ? item.entities.array : item.secondCategoryRows.array
            for (sIdx, sub) in secondRows.enumerated() {
                if !sub.entities.array.isEmpty {
                    for (eIdx, ent) in sub.entities.array.enumerated() {
                        let link = iconLink(from: ent, parentCard: sub, keyPrefix: "pcat-\(idx)-\(sIdx)-\(eIdx)")
                        if !link.title.isEmpty {
                            links.append(link)
                        }
                    }
                } else {
                    let link = iconLink(from: sub, parentCard: item, keyPrefix: "pcat-\(idx)-\(sIdx)")
                    if !link.title.isEmpty {
                        links.append(link)
                    }
                }
            }
            if !links.isEmpty {
                groups.append(ProductCategoryGroup(
                    id: "pcatgrp-\(idx)-\(item.entityId.identifier)-\(groupTitle)",
                    title: groupTitle,
                    logo: groupLogo,
                    items: links
                ))
            }
        }
        return groups
    }

    public static func userRatingFeeds(uid: String, targetType: String = "all", page: Int) async throws -> [HomeFeedRow] {
        try await linkFeed(link: "/feed/nodeRatingList?uid=\(uid)&targetType=\(targetType)&parseRatingToFeed=1", page: page)
    }

    public static func reviewFeeds(page: Int) async throws -> [HomeFeedRow] {
        for tag in ["数码测评", "评测", "深度评测"] {
            if let rows = try? await topicFeeds(tag: tag, page: page, listType: "lastupdate_desc"), !rows.isEmpty {
                return rows
            }
        }
        if let raw = try? await search(keyword: "评测", type: "feed", page: page) {
            let mapped = rows(from: raw)
            if !mapped.isEmpty { return mapped }
        }
        return []
    }

    public static func goodsRecommendationFeed(page: Int) async throws -> [HomeFeedRow] {
        if let v11 = try? await pageFeed(pageName: "V11_FIND_GOODS", page: page), !v11.isEmpty {
            return v11
        }
        if let json = try? await client.get("/v6/goodsList/list", ["page": String(page)]) {
            let parsed = rows(from: json.data.array)
            if !parsed.isEmpty { return parsed }
        }
        if let feedList = try? await pageFeed(pageName: "/goods/feedList", page: page), !feedList.isEmpty {
            return feedList
        }
        if let ershouHome = try? await pageFeed(pageName: "V11_FIND_GOOD_GOODS_HOME", page: page), !ershouHome.isEmpty {
            return ershouHome
        }
        return (try? await topicFeeds(tag: "好物推荐", page: page)) ?? []
    }

    public static func userEquipmentFeed(uid: String, type: String = "owner", page: Int) async throws -> [HomeFeedRow] {
        let cleanUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [(String, [String: String])] = [
            ("#/product/productList?type=\(type)&uid=\(cleanUID)", ["uid": cleanUID, "type": type]),
            ("/product/productList?type=\(type)&uid=\(cleanUID)", ["uid": cleanUID, "type": type]),
            ("#/product/productList?type=\(type)", ["uid": cleanUID, "type": type]),
            ("/user/productList?uid=\(cleanUID)&type=\(type)", ["uid": cleanUID, "type": type])
        ]
        for (urlPath, extra) in candidates {
            if let items = try? await client.dataList(url: urlPath, page: page, extra: extra) {
                let mapped = rows(from: items)
                if !mapped.isEmpty { return mapped }
            }
        }
        let directPaths = ["/v6/user/productList", "/v6/product/productList"]
        for path in directPaths {
            if let json = try? await client.get(path, ["uid": cleanUID, "type": type, "page": String(page)], clearProofOnCaptcha: false) {
                let mapped = rows(from: json.data.array)
                if !mapped.isEmpty { return mapped }
            }
        }
        // Fallback: search user's feeds mentioning digital products or ratings
        if !cleanUID.isEmpty, let ratingRows = try? await userRatingFeeds(uid: cleanUID, targetType: "product", page: page), !ratingRows.isEmpty {
            return ratingRows
        }
        return []
    }
}
