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
}
