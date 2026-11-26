import XCTest
@testable import CoolapkKit

final class JSONAndAPITests: XCTestCase {
    func testJSONCoercesMixedTypes() throws {
        let data = Data(#"{"id":12345,"strId":"67890","flag":"1","extra":"{\"showCancelFollowMenu\":1}"}"#.utf8)
        let json = try JSON(data: data)
        XCTAssertEqual(json.id.identifier, "12345")
        XCTAssertEqual(json.strId.int, 67890)
        XCTAssertTrue(json.flag.bool)
        XCTAssertEqual(json.extra.parsed.showCancelFollowMenu.int, 1)
    }

    func testPageTargetUnwrapsCoolapkLink() {
        XCTAssertEqual(API.pageTarget(from: "/page?url=V9_HOME_TAB_RANKING&title=热榜"), "V9_HOME_TAB_RANKING")
        XCTAssertEqual(API.pageTarget(from: "#/topic/tagList?type=hot"), "/topic/tagList?type=hot")
    }

    func testRowsGroupsGoodsAndSkipsAds() throws {
        let raw = Data("""
        [
          {"entityType":"card","entityTemplate":"adCard","title":"广告"},
          {"entityType":"pear_goods","id":"1","title":"商品A","goods_promo_price":99.5},
          {"entityType":"pear_goods","id":"2","title":"商品B","goods_promo_price":199},
          {"entityType":"feed","id":1001,"username":"测试","message":"你好酷安"}
        ]
        """.utf8)
        let items = try JSON(data: raw).array
        let rows = API.rows(from: items)
        XCTAssertEqual(rows.count, 2)
        if case let .goods(_, list) = rows[0] {
            XCTAssertEqual(list.count, 2)
            XCTAssertEqual(list[0].price, "¥99.50")
        } else {
            XCTFail("Expected grouped goods row")
        }
        if case let .feed(feed) = rows[1] {
            XCTAssertEqual(feed.id, "1001")
        } else {
            XCTFail("Expected feed row")
        }
    }
}
