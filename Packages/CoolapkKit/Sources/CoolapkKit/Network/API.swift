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
        let json = try await client.get(
            "/v6/main/indexV8",
            ["page": String(page), "t": String(Int(Date().timeIntervalSince1970))],
            base: CoolapkClient.api2Base
        )
        return rows(from: json.data.array)
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
        let json = try await client.get("/v6/picture/list", [
            "tag": tag,
            "type": type,
            "page": String(page)
        ])
        return rows(from: json.data.array)
    }

    public static let followPageName = "V9_HOME_TAB_FOLLOW"

    public static func pageFeed(pageName: String, page: Int, type: String? = nil) async throws -> [HomeFeedRow] {
        var extra: [String: String] = [:]
        if let type { extra["type"] = type }
        let items = try await client.dataList(url: pageName, page: page, extra: extra)
        return rows(from: items)
    }

    public static func linkFeed(link: String, page: Int) async throws -> [HomeFeedRow] {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/user/dyhSubscribe" || trimmed == "/v6/user/dyhSubscribe" {
            return try await dyhSubscribe(page: page)
        }
        if trimmed.hasPrefix("/v6/") {
            let json = try await client.get(trimmed, ["page": String(page)])
            return rows(from: json.data.array)
        }
        let parsed = parsePageLink(trimmed)
        let items = try await client.dataList(url: parsed.url, page: page, extra: parsed.extra)
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
        let items = try await client.dataList(url: parsed.url, page: page, extra: parsed.extra)
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
        if let tabURL = tabURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tabURL.isEmpty,
           !tabURL.hasPrefix("/product/"),
           tabURL != "/product/\(productID)" {
            let loaded = (try? await linkFeed(link: tabURL, page: page)) ?? []
            if !loaded.isEmpty { return loaded }
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

    private static func parsePageLink(_ link: String) -> (url: String, extra: [String: String]) {
        var clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("coolapk://") {
            clean = String(clean.dropFirst("coolapk://".count))
            if !clean.hasPrefix("/") { clean = "/" + clean }
        }
        if clean.hasPrefix("/page?") || clean.hasPrefix("page?"),
           let components = URLComponents(string: clean.hasPrefix("/") ? clean : "/\(clean)"),
           let queryItems = components.queryItems {
            var targetURL = ""
            var extra: [String: String] = [:]
            for item in queryItems {
                guard let value = item.value, !value.isEmpty else { continue }
                if item.name == "url" {
                    targetURL = value
                } else {
                    extra[item.name] = value
                }
            }
            if !targetURL.isEmpty {
                return (targetURL.replacingOccurrences(of: "#", with: ""), extra)
            }
        }
        return (pageTarget(from: clean), [:])
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
        "iconButtonGridCard", "iconLargeScrollCard", "imageSquareScrollCard",
    ]

    private static let linkBarTemplates: Set<String> = [
        "selectorLinkCard", "sortSelectCard", "capsuleListCard", "colorfulScrollCard",
        "iconTabLinkGridCard", "tabGroupCard",
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
            switch item.entityType.string {
            case "feed", "feed_reply", "reply", "forwardFeed", "feedLike", "like":
                let payload = item.feedInfo.exists ? item.feedInfo : item
                rows.append(.feed(FeedItem(json: payload)))
            case "history", "recentHistory":
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
                    rows.append(.feed(FeedItem(json: item.feedInfo)))
                } else if !item.message.string.isEmpty && !item.uid.identifier.isEmpty {
                    rows.append(.feed(FeedItem(json: item)))
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
        return rows
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

        if !entities.isEmpty, entities.allSatisfy({ $0.entityType.string == "pear_goods" }) {
            return titled([.goods("goods-\(index)", entities.map { PearGoods(json: $0) })])
        }

        if template == "eventCard" || template == "activityCard" {
            let events = entities.map { EventItem(json: $0) }.filter { !$0.title.isEmpty || !$0.cover.isEmpty }
            if !events.isEmpty { return titled(events.map { HomeFeedRow.event($0) }) }
        }

        if template == "listCard" || template == "productTimelineListCard" {
            let eventEntities = entities.filter {
                $0.entityType.string == "event" || $0.url.string.contains("/event/")
            }
            if !eventEntities.isEmpty && eventEntities.count == entities.count {
                return titled(eventEntities.map { HomeFeedRow.event(EventItem(json: $0)) })
            }
            let products = entities
                .filter { !$0.logo.string.isEmpty || $0.price_min.exists }
                .map { ProductItem(json: $0) }
            if let only = products.first, products.count == 1 { return titled([.product(only)]) }
            if !products.isEmpty { return titled(products.prefix(8).map { HomeFeedRow.product($0) }) }
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

        if !entities.isEmpty, entities.allSatisfy({ $0.entityType.string == "event" || $0.url.string.contains("/event/") }) {
            let events = entities.map { EventItem(json: $0) }.filter { !$0.title.isEmpty || !$0.cover.isEmpty }
            if !events.isEmpty { return titled(events.map { HomeFeedRow.event($0) }) }
        }

        if iconCardTemplates.contains(template) {
            let links = entities.enumerated().map { offset, entity in
                iconLink(from: entity, keyPrefix: "icon-\(index)-\(offset)")
            }.filter { !$0.image.isEmpty || !$0.title.isEmpty }
            if links.isEmpty { return [] }
            if links.allSatisfy({ $0.image.isEmpty }) {
                let sections = links.map { HomeSection(id: $0.id, title: $0.title, subtitle: $0.subtitle, url: $0.url, style: "") }
                return titled([.linkList("linklist-\(index)", sections)])
            }
            return titled([.icons("icons-\(index)", links)])
        }

        if linkBarTemplates.contains(template) {
            let links = entities.enumerated()
                .map { offset, entity in
                    HomeSection(
                        id: "lbar-\(index)-\(offset)-\(entity.entityId.identifier)",
                        title: entity.title.string,
                        subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string,
                        url: entity.url.string,
                        style: entity.pic.string
                    )
                }
                .filter { !$0.title.isEmpty }
            return links.isEmpty ? [] : titled([.linkBar("linkbar-\(index)", links)])
        }

        switch template {
        case "imageCarouselCard_1", "imageCarouselCard_2", "imageCarouselCard":
            let banners = entities.enumerated().compactMap { offset, entity -> HomeBanner? in
                let image = entity.pic.string
                guard !image.isEmpty else { return nil }
                return HomeBanner(
                    id: "car-\(index)-\(offset)-\(entity.entityId.identifier)",
                    title: entity.title.string.isEmpty ? entity.description.string : entity.title.string,
                    subtitle: entity.sub_title.string,
                    image: image,
                    url: entity.url.string
                )
            }
            return banners.isEmpty ? [] : [.banners("banner-\(index)", banners)]

        case "imageTextScrollCard":
            let allEvents = !entities.isEmpty && entities.allSatisfy {
                $0.entityType.string == "event" || $0.url.string.contains("/event/")
            }
            if allEvents {
                return titled(entities.map { HomeFeedRow.event(EventItem(json: $0)) })
            }
            let sections = entities.enumerated().map { offset, entity in
                HomeSection(
                    id: "sec-\(index)-\(offset)-\(entity.entityId.identifier)",
                    title: entity.title.string,
                    subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string,
                    url: entity.url.string,
                    style: entity.pic.string
                )
            }
            return sections.isEmpty ? [] : [.sections("sections-\(index)", sections)]

        case "verticalColumnsFullPageCard":
            let columns = entities.enumerated()
                .map { offset, entity in
                    HomeSection(
                        id: "col-\(index)-\(offset)-\(entity.entityId.identifier)",
                        title: entity.title.string,
                        subtitle: entity.sub_title.string,
                        url: entity.url.string,
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
            if entities.count == 1, let entity = entities.first {
                return [.feed(FeedItem(json: entity))]
            }
            return title.isEmpty ? [] : [.sectionTitle(key: "\(index)", title: title, url: moreURL, subtitle: "")]

        default:
            let links = entities.enumerated().map { offset, entity in
                iconLink(from: entity, keyPrefix: "def-\(index)-\(offset)")
            }.filter { !$0.image.isEmpty }
            if !links.isEmpty { return titled([.icons("icons-\(index)", links)]) }
            if !title.isEmpty, entities.isEmpty { return [.text("text-\(index)", title)] }
        }
        return []
    }

    private static func iconLink(from entity: JSON, keyPrefix: String = "icon") -> HomeIconLink {
        HomeIconLink(
            id: "\(keyPrefix)-\(entity.entityId.identifier)-\(entity.title.string)",
            title: entity.title.string,
            image: entity.logo.string.isEmpty ? entity.pic.string : entity.logo.string,
            url: entity.url.string,
            subtitle: entity.sub_title.string.isEmpty ? entity.description.string : entity.sub_title.string
        )
    }

    // MARK: - Feed Detail & Replies

    public static func feedDetail(id: String, allowPublicFallback: Bool = true) async throws -> FeedItem {
        do {
            let json = try await client.get("/v6/feed/detail", ["id": id])
            return FeedItem(json: json.data)
        } catch let error as APIError {
            if allowPublicFallback {
                switch error {
                case .captchaRequired, .unauthorized:
                    if let pub = try? await client.publicFeedJSON(id: id) {
                        return FeedItem(json: pub.data)
                    }
                default:
                    break
                }
            }
            throw error
        }
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
            // Use primary apiBase first so cookies/SESSID/szlm stay consistent across endpoints.
            let json = try await client.get("/v6/feed/replyList", query, base: CoolapkClient.apiBase)
            return json.data.array
                .filter { ReplyItem.isValidReplyJSON($0) }
                .map { ReplyItem(json: $0) }
        } catch let error as APIError {
            if case .captchaRequired = error {
                if let fallback = try? await client.get("/v6/feed/replyList", query, base: CoolapkClient.api2Base) {
                    return fallback.data.array
                        .filter { ReplyItem.isValidReplyJSON($0) }
                        .map { ReplyItem(json: $0) }
                }
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
        _ = try await client.post(follow ? "/v6/feed/followTag" : "/v6/feed/unFollowTag", ["tag": tag])
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

    public static func createFeed(message: String, pictures: [String]) async throws {
        var form: [String: String] = [
            "message": message,
            "type": "feed",
            "is_html_article": "0",
            "status": "1",
            "publish_status": "0"
        ]
        if !pictures.isEmpty {
            form["pics"] = pictures.joined(separator: ",")
            form["picArr"] = pictures.joined(separator: ",")
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
        let json = try await client.get("/v6/user/profile", ["uid": uid])
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
        return LoginCheckResult(isValid: true)
    }

    public static func checkLogin() async throws -> Bool {
        let result = try await checkLoginInfo()
        return result.isValid && !result.explicitlyInvalid
    }

    // MARK: - Search

    public static func search(keyword: String, type: String, page: Int) async throws -> [JSON] {
        let json = try await client.get("/v6/search", [
            "type": type,
            "searchValue": keyword,
            "page": String(page),
            "showAnonymous": "-1",
        ])
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
        let json = try await client.get("/v6/apk/detail", ["id": id, "installed": "0"])
        return AppItem(json: json.data)
    }

    public static func appComments(id: String, page: Int) async throws -> [HomeFeedRow] {
        let items = try await client.dataList(url: "#/feed/apkCommentList?isIncludeTop=1&id=\(id)&subTitle=", page: page)
        return rows(from: items)
    }

    public static func collectionList(uid: String?, page: Int) async throws -> [CollectionItem] {
        let uid = uid ?? ""
        let json = try await client.get("/v6/collection/list", ["uid": uid, "page": String(page)])
        return json.data.array.map { CollectionItem(json: $0) }
    }

    public static func collectionDetail(id: String) async throws -> CollectionItem {
        let json = try await client.get("/v6/collection/detail", ["id": id])
        return CollectionItem(json: json.data)
    }

    public static func collectionItems(id: String, page: Int) async throws -> [HomeFeedRow] {
        let json = try await client.get("/v6/collection/itemList", ["id": id, "page": String(page)])
        return rows(from: json.data.array)
    }

    public static func followCollection(id: String, follow: Bool) async throws {
        _ = try await client.post(follow ? "/v6/collection/follow" : "/v6/collection/unFollow", ["id": id])
    }

    public static func dyhDetail(id: String) async throws -> DyhItem {
        let json = try await client.get("/v6/dyh/detail", ["dyhId": id])
        return DyhItem(json: json.data)
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
        _ = try await client.post(follow ? "/v6/dyh/follow" : "/v6/dyh/unFollow", ["dyhId": id])
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
        let json = try await client.get("/v6/notification/\(type)", ["page": String(page)])
        return json.data.array.map { NotificationItem(json: $0) }
    }

    public static func messageThreads(page: Int) async throws -> [MessageThread] {
        let json = try await client.get("/v6/message/list", ["page": String(page)])
        return json.data.array.map { MessageThread(json: $0) }
    }

    public static func chatMessages(ukey: String, page: Int) async throws -> [ChatMessage] {
        let json = try await client.get("/v6/message/chat", ["ukey": ukey, "page": String(page)])
        return json.data.array.map { ChatMessage(json: $0) }
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
}
