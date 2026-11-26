import XCTest
@testable import CoolapkKit

final class ModelTests: XCTestCase {
    func testFeedItemParsesArticleAndMediaMetadata() throws {
        let raw = Data("""
        {
          "id": 9988,
          "uid": 100,
          "username": "数码君",
          "feedType": "feedArticle",
          "message_title": "深度体验",
          "message_cover": "http://image.coolapk.com/cover.jpg",
          "message_raw_output": "[{\\"type\\":\\"text\\",\\"message\\":\\"第一段\\"},{\\"type\\":\\"image\\",\\"url\\":\\"http://image.coolapk.com/p1.jpg\\",\\"description\\":\\"样张\\"}]",
          "image_uri_list": [
            {"url": "http://image.coolapk.com/live.jpg", "videoUrl": "http://image.coolapk.com/live.mp4", "isHdr": 1}
          ],
          "topReplyRows": [{"id": 55, "uid": 100, "username": "数码君", "message": "置顶说明"}]
        }
        """.utf8)
        let feed = FeedItem(json: try JSON(data: raw))
        XCTAssertEqual(feed.kind, .feedArticle)
        XCTAssertEqual(feed.cover, "https://image.coolapk.com/cover.jpg")
        XCTAssertEqual(feed.articleParts.count, 2)
        XCTAssertEqual(feed.mediaItems.count, 1)
        XCTAssertTrue(feed.mediaItems[0].isLivePhoto)
        XCTAssertTrue(feed.mediaItems[0].isHdr)
        XCTAssertEqual(feed.mediaItems[0].videoUrl, "https://image.coolapk.com/live.mp4")
        XCTAssertEqual(feed.topReplyRows.first?.isTop, true)
    }

    func testHomeTabConfigAlwaysKeepsFeedVisible() {
        let config = HomeTabConfiguration(order: [.hot, .topic], hidden: [.feed, .hot])
        XCTAssertFalse(config.hidden.contains(.feed))
        XCTAssertTrue(config.visibleTabs.contains(.feed))
        XCTAssertFalse(config.visibleTabs.contains(.hot))
    }

    func testNotificationItemUsesLikeActorInsteadOfPostAuthor() throws {
        let raw = Data("""
        {
          "id": 123,
          "type": "feedlike",
          "username": "原帖作者",
          "likeUid": 888,
          "likeUsername": "点赞者",
          "likeAvatar": "https://image.coolapk.com/a.jpg",
          "feedTypeName": "动态"
        }
        """.utf8)
        let item = NotificationItem(json: try JSON(data: raw))
        XCTAssertEqual(item.username, "点赞者")
        XCTAssertEqual(item.action, "赞了你的动态")
    }

    func testUserProfileDoesNotTreatFollowCountAsIsFollowed() throws {
        let raw = Data("""
        {
          "uid": 2024,
          "username": "测试用户",
          "follow": 48,
          "fans": 120,
          "isFollowed": 0
        }
        """.utf8)
        let profile = UserProfile(json: try JSON(data: raw))
        XCTAssertEqual(profile.followNum, 48)
        XCTAssertFalse(profile.isFollowed)

        let followedRaw = Data("""
        {
          "uid": 2025,
          "username": "已关注用户",
          "follow": 12,
          "isFollowed": 1
        }
        """.utf8)
        let followedProfile = UserProfile(json: try JSON(data: followedRaw))
        XCTAssertTrue(followedProfile.isFollowed)
    }

    func testMediaHintsAndSecondHandAndLoginTimeParsing() throws {
        let raw = Data("""
        {
          "id": 7788,
          "uid": 99,
          "username": "极客卖家",
          "feedType": "ershou",
          "feedTypeName": "二手",
          "message_title": "出闲置平板",
          "message": "成色极佳 <a href=\\"https://h5.m.goofish.com/item?id=123\\">闲鱼</a>",
          "ershou_price": 1899,
          "orig_price": 2999,
          "city": "上海",
          "extra_title": "闲鱼商品",
          "extra_url": "https://h5.m.goofish.com/item?id=123",
          "device_title": "iPhone 17 Pro",
          "logintime": 1700000000,
          "picArr": [
            "http://image.coolapk.com/shot-livepic.jpg",
            "http://image.coolapk.com/sunset-xhdr.jpg"
          ]
        }
        """.utf8)
        let feed = FeedItem(json: try JSON(data: raw))
        XCTAssertTrue(feed.isSecondHand)
        XCTAssertEqual(feed.priceText, "¥1899")
        XCTAssertEqual(feed.originalPriceText, "¥2999")
        XCTAssertEqual(feed.cityText, "上海")
        XCTAssertEqual(feed.xianyuURL, "https://h5.m.goofish.com/item?id=123")
        XCTAssertNotNil(feed.authorLoginTime)
        XCTAssertEqual(feed.mediaItems.count, 2)
        XCTAssertTrue(feed.mediaItems[0].isLivePhoto)
        XCTAssertTrue(feed.mediaItems[1].isHdr)
    }

    func testFeedZeroFidPreservesIDAndTopicAndConfigInfoParsing() throws {
        let feedData = Data("""
        {
          "entityType": "feed",
          "id": 543210,
          "fid": 0,
          "uid": 100,
          "username": "测试作者",
          "message": "一条完整动态"
        }
        """.utf8)
        let feed = FeedItem(json: try JSON(data: feedData))
        XCTAssertEqual(feed.id, "543210")
        XCTAssertEqual(feed.effectiveFeedID, "543210")
        XCTAssertFalse(feed.needsDetailRefresh)

        let topicData = Data("""
        {
          "id": 88,
          "title": "鸿蒙OS",
          "feed_num": 0,
          "commentnum": 1280,
          "follownum": 420,
          "hot_num_txt": "2.5万"
        }
        """.utf8)
        let topic = TopicItem(json: try JSON(data: topicData))
        XCTAssertEqual(topic.feedNum, 1280)
        XCTAssertEqual(topic.followNum, 420)
        XCTAssertEqual(topic.hotNum, 25000)

        let configData = Data("""
        {
          "status": 1,
          "dataRows": {
            "基本信息": [
              {"type": "groupData", "keyName": "核心硬件", "depth": 1},
              {"type": "itemData", "data": {"title": "处理器", "unit": "", "show_value": "骁龙8至尊版", "addition_value": "-"}}
            ]
          }
        }
        """.utf8)
        let sections = ProductSpecSection.sections(fromConfigInfoJSON: try JSON(data: configData))
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].items.first?.label, "处理器")
        XCTAssertEqual(sections[0].items.first?.value, "骁龙8至尊版")
        XCTAssertEqual(sections[0].items.first?.group, "核心硬件")
    }

    func testSecondHandObjectExtraDataRedirectAndDuplicatePicsDoNotForceReload() throws {
        let secondHandRaw = Data("""
        {
          "entityType": "feed",
          "id": 991234,
          "uid": 500,
          "username": "出闲置用户",
          "feedType": "ershou",
          "feedTypeName": "二手交易",
          "message": "自用平板，成色很新，走平台担保。",
          "extraData": {
            "price": 1599,
            "url": "/link?url=https%3A%2F%2Fm.tb.cn%2Fh.abc123",
            "title": "闲鱼链接 · 小米平板"
          },
          "pic": "http://image.coolapk.com/p1.jpg",
          "picArr": [
            "https://image.coolapk.com/p1.jpg",
            "https://image.coolapk.com/p1.jpg"
          ],
          "is_long_feed": 1
        }
        """.utf8)
        let feed = FeedItem(json: try JSON(data: secondHandRaw))
        XCTAssertTrue(feed.isSecondHand)
        XCTAssertEqual(feed.priceText, "¥1599")
        XCTAssertEqual(feed.extraURL, "https://m.tb.cn/h.abc123")
        XCTAssertTrue(FeedItem.isXianyuOrTradeURL(feed.extraURL))
        XCTAssertFalse(feed.needsDetailRefresh)
    }

    func testTopicTabListAndFeedMultipleRelationEntitiesParsing() throws {
        let topicJSON = Data("""
        {
          "id": 12345,
          "title": "薅羊毛小分队",
          "selectedTab": "deals",
          "tabList": [
            {"title": "精选", "page_name": "selected", "url": "#/page?url=/topic/selected"},
            {"title": "搜神券", "page_name": "deals", "url": "#/page?url=/topic/deals"},
            {"title": "讨论", "page_name": "discuss", "url": "#/topic/feedList?tag=薅羊毛小分队"}
          ]
        }
        """.utf8)
        let topic = TopicItem(json: try JSON(data: topicJSON))
        XCTAssertEqual(topic.selectedTab, "deals")
        XCTAssertEqual(topic.tabs.map(\.title), ["精选", "搜神券", "讨论"])
        XCTAssertEqual(topic.tabs.map(\.subtitle), ["selected", "deals", "discuss"])

        let multiTagFeedJSON = Data("""
        {
          "id": 654321,
          "uid": 100,
          "username": "多话题玩家",
          "message": "分享好价与评测",
          "targetRow": {"id": "1", "title": "小米15", "url": "/product/1001", "targetType": "product"},
          "relationRows": [
            {"id": "1", "title": "小米15", "url": "/product/1001", "entityType": "product"},
            {"id": "2", "title": "薅羊毛小分队", "url": "/t/薅羊毛小分队", "entityType": "topic"},
            {"id": "3", "title": "好物推荐", "url": "/t/好物推荐", "entityType": "topic"}
          ],
          "tags": "好物推荐,摄影打卡"
        }
        """.utf8)
        let feed = FeedItem(json: try JSON(data: multiTagFeedJSON))
        XCTAssertEqual(feed.relationEntities.map(\.title), ["小米15", "薅羊毛小分队", "好物推荐", "摄影打卡"])
        XCTAssertEqual(feed.relationEntities.last?.url, "/t/摄影打卡")

        XCTAssertEqual(
            FeedLink.inferredPageTitle(from: "/page?url=%2Ffeed%2FrankList%3Ftype%3Dweek&title=%E5%91%A8%E6%A6%9C"),
            "周榜"
        )
        XCTAssertEqual(
            FeedLink.resolve("coolmarket:///#/ranking/weekList?title=热榜"),
            .page("#/ranking/weekList?title=热榜")
        )
        XCTAssertEqual(
            FeedLink.resolve("/feed/rankList?type=month"),
            .page("/feed/rankList?type=month")
        )
        XCTAssertEqual(
            FeedLink.resolve("/feed/123456"),
            .feed("123456")
        )
        XCTAssertEqual(
            FeedLink.resolve("/product/categoryList"),
            .page("/product/categoryList")
        )
    }

    func testErshouInfoProductPriceLinkUrlAndCompletedStatus() throws {
        let activeRaw = Data("""
        {
          "entityType": "feed",
          "id": 75284719,
          "uid": 1001,
          "username": "数码卖家",
          "message": "自用成色很好",
          "ershou_info": {
            "product_price": "1999",
            "product_title": "闲鱼二手好物",
            "link_source": "闲鱼",
            "link_url": "https://h5.m.goofish.com/item?id=75284719",
            "province": "广东",
            "city": "深圳",
            "ershou_status": 1
          }
        }
        """.utf8)
        let activeFeed = FeedItem(json: try JSON(data: activeRaw))
        XCTAssertTrue(activeFeed.isSecondHand)
        XCTAssertEqual(activeFeed.priceText, "¥1999")
        XCTAssertEqual(activeFeed.xianyuURL, "https://h5.m.goofish.com/item?id=75284719")
        XCTAssertEqual(activeFeed.extraTitle, "闲鱼二手好物")
        XCTAssertEqual(activeFeed.cityText, "广东 深圳")
        XCTAssertEqual(activeFeed.dealStatusText, "")

        let completedRaw = Data("""
        {
          "entityType": "feed",
          "id": 75282142,
          "uid": 1002,
          "username": "已成交用户",
          "message": "感谢平台",
          "ershou_info": {
            "product_price": 1250,
            "link_source": "转转",
            "link_url": "https://m.zhuanzhuan.com/detail/123",
            "city": "杭州",
            "ershou_status": -1
          }
        }
        """.utf8)
        let completedFeed = FeedItem(json: try JSON(data: completedRaw))
        XCTAssertTrue(completedFeed.isSecondHand)
        XCTAssertEqual(completedFeed.priceText, "¥1250")
        XCTAssertEqual(completedFeed.dealStatusText, "交易完成")
        XCTAssertEqual(completedFeed.xianyuURL, "https://m.zhuanzhuan.com/detail/123")
    }
}
