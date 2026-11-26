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
}
