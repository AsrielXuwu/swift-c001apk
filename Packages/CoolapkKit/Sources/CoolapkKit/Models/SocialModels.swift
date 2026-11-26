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
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
        gender = json.gender.int
        registerDate = json.regdate.date
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

    public init(json: JSON) {
        id = json.uid.exists ? json.uid.identifier : json.entityId.identifier
        username = json.username.string
        avatar = json.userAvatar.string.isEmpty ? json.avatar.string : json.userAvatar.string
        level = json.level.int
        isFollowed = json.isFollowed.int > 0
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

public struct ProductItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String
    public var logo: String
    public var description: String
    public var score: String
    public var followNum: Int
    public var isFollowed: Bool
    public var url: String

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        subtitle = json.sub_title.string.isEmpty ? json.description.string : json.sub_title.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        description = json.description.string
        score = json.score.string.isEmpty ? json.avg_score.string : json.score.string
        followNum = json.follow_num.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
        url = json.url.string
    }
}

public struct TopicItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var description: String
    public var logo: String
    public var feedNum: Int
    public var followNum: Int
    public var isFollowed: Bool

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        description = json.description.string
        logo = json.logo.string.isEmpty ? json.pic.string : json.logo.string
        feedNum = json.feed_num.int
        followNum = json.follow_num.int
        isFollowed = json.isFollowed.int > 0 || json.follow.int > 0
            || json.extraData.parsed.showCancelFollowMenu.int > 0
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

    public init(json: JSON) {
        id = json.id.exists ? json.id.identifier : json.entityId.identifier
        title = json.title.string
        description = json.description.string
        cover = json.pic.string.isEmpty ? json.cover.string : json.pic.string
        url = json.url.string
        startTimeText = json.dateline_text.string
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
        }
    }

    public var date: Date? {
        if case let .feed(item) = self { return item.dateline }
        return nil
    }
}
