import XCTest
@testable import CoolapkKit

final class ContentEngineTests: XCTestCase {
    func testHTMLParserExtractsEmojiLinksAndCoinReply() {
        let html = "你好 <a href=\"/t/iOS27\">#iOS27#</a> [滑稽]<br>第二行"
        let tokens = FeedHTMLParser.tokenize(html)
        XCTAssertTrue(tokens.contains(.emoji(name: "[滑稽]")))
        XCTAssertTrue(tokens.contains(.newline))
        XCTAssertEqual(FeedLink.resolve("/t/iOS27"), .topic("iOS27"))
        XCTAssertEqual(FeedLink.resolve("coolmarket://feed/12345"), .feed("12345"))

        XCTAssertTrue(FeedHTMLParser.isCoinOnlyReply(message: "[酷币] [酷币5毛]", pics: []))
        XCTAssertFalse(FeedHTMLParser.isCoinOnlyReply(message: "[酷币] 支持一下", pics: []))
    }

    func testContentFilterRespectsLevelExceptionsAndAllowList() {
        let engine = ContentFilterEngine(ruleSet: BuiltinFilterRules.defaultRuleSet)
        let strictInput = FilterInput(scope: .feed, id: "1", authorUID: "2", text: "求女菩萨发福利")
        XCTAssertNil(engine.evaluate(strictInput, level: .standard))
        XCTAssertNotNil(engine.evaluate(strictInput, level: .strict))

        let exempted = FilterInput(scope: .feed, id: "2", authorUID: "3", text: "请坚决举报想约炮的骚扰私信")
        XCTAssertNil(engine.evaluate(exempted, level: .standard))

        let topicHit = FilterInput(scope: .feed, id: "3", authorUID: "4", text: "普通内容", topicNames: ["我在酷安晒女友"])
        XCTAssertNotNil(engine.evaluate(topicHit, level: .standard))
        XCTAssertNil(engine.evaluate(topicHit, level: .standard, allowedAuthorUIDs: ["4"]))
    }

    func testExportEscapesHTMLAndSelectsPinnedComments() throws {
        let feedJSON = try JSON(data: Data("""
        {
          "id": 42,
          "username": "作者<script>",
          "message_title": "标题 & 测试",
          "message": "正文<br>内容",
          "picArr": ["http://image.coolapk.com/1.jpg"]
        }
        """.utf8))
        let feed = FeedItem(json: feedJSON)
        let pinned = ReplyItem(json: try JSON(data: Data(#"{"id":1,"uid":10,"username":"置顶用户","message":"置顶评论","likenum":5}"#.utf8)), forcedTop: true)
        let blocked = ReplyItem(json: try JSON(data: Data(#"{"id":2,"uid":99,"username":"黑名单用户","message":"屏蔽我","likenum":999}"#.utf8)))
        let selected = ExportDocument.selectExportComments(pinned: [pinned], popular: [blocked], blockedUIDs: ["99"])
        XCTAssertEqual(selected.map(\.id), ["1"])

        let doc = ExportDocument.fromFeed(feed, comments: selected, notices: ["测试说明"])
        XCTAssertTrue(doc.markdown.contains("标题 & 测试"))
        let html = doc.offlineHTML(embeddedImages: ["https://image.coolapk.com/1.jpg": "data:image/png;base64,AAAA"])
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("data:image/png;base64,AAAA"))
    }
}
