import XCTest
@testable import CoolapkKit

final class AuthAndIdentityTests: XCTestCase {
    func testDeviceCodeIsNonEmptyAndValidBase64Reversed() {
        let code = CoolapkToken.makeDeviceCode()
        XCTAssertFalse(code.isEmpty)
        XCTAssertFalse(code.contains("="))
    }

    func testReplacingDeviceIdentifierUpdatesSlotZeroAndPreservesFields() {
        let original = CoolapkToken.makeDeviceCode(brand: "Xiaomi", model: "24129PN74C")
        let originalFields = CoolapkToken.decodeDeviceFields(original)
        XCTAssertEqual(originalFields?.count, 9)

        let fakeDUID = "DUMqtb1J4vCLYfS5OeVLfgeLAZqlvLqPnogbU"
        let replaced = CoolapkToken.replacingDeviceIdentifier(in: original, with: fakeDUID)
        let replacedFields = CoolapkToken.decodeDeviceFields(replaced)
        XCTAssertEqual(replacedFields?.count, 9)
        XCTAssertEqual(replacedFields?.first, fakeDUID)
        XCTAssertEqual(Array(replacedFields?.dropFirst() ?? []), Array(originalFields?.dropFirst() ?? []))

        let params = ProtocolParameters(deviceCode: original, szlmID: fakeDUID)
        XCTAssertEqual(CoolapkToken.decodeDeviceFields(params.deviceCode)?.first, fakeDUID)
    }

    func testTokenV3GeneratesCanonicalPrefix() {
        let device = CoolapkToken.makeDeviceCode()
        let token = CoolapkToken.appTokenV3(deviceCode: device, timestamp: 1_760_000_000, appCode: 2604201)
        XCTAssertNotNil(token)
        XCTAssertTrue(token?.hasPrefix("v3") == true)
    }

    func testOfficialDeviceIdentityRejectsAllZeroAndInvalidInputs() {
        XCTAssertNil(OfficialDeviceIdentity.validate("0000000000000000"))
        XCTAssertNil(OfficialDeviceIdentity.validate("short"))
        XCTAssertEqual(OfficialDeviceIdentity.validate("  Valid_ShuzlmID_123456  "), "Valid_ShuzlmID_123456")
    }

    func testOfficialDeviceIdentityParsesCopiedOAIDBlock() throws {
        let sample = """
        OAID: abc
        ShuzlmID：D_A1b2C3d4E5f6G7h8
        AndroidID: 123
        """
        let parsed = try OfficialDeviceIdentity.parse(sample)
        XCTAssertEqual(parsed, "D_A1b2C3d4E5f6G7h8")
    }

    func testSzlmDuidReportRoundTripAndDecode() throws {
        let seed = "0123456789abcdef0123456789abcdef"
        let report = try SzlmDuidClient.buildReport(seed: seed, timestamp: "1760000000.123456789")
        let encoded = try SzlmDuidClient.encodeReport(report)
        XCTAssertFalse(encoded.isEmpty)

        let mockJSON = #"{"err":"0","n_a":"VALID_SZLM_ID_987654321"}"#
        let compressed = try SzlmDuidClient.zlibCompress(Data(mockJSON.utf8))
        let responsePayload = SzlmDuidClient.xor(compressed)
        XCTAssertEqual(SzlmDuidClient.decodeID(from: responsePayload), "VALID_SZLM_ID_987654321")

        let zeroPayload = SzlmDuidClient.xor(Data(#"{"err":"0","n_a":"000000000000"}"#.utf8))
        XCTAssertNil(SzlmDuidClient.decodeID(from: zeroPayload))
    }

    func testCaptchaChallengeExtractionAndProofFormat() throws {
        let raw = Data(#"{"messageStatus":"err_request_captcha_v2","messageExtra":{"captchaId":"1234567890abcdef1234567890abcdef","captchaField":""}}"#.utf8)
        let json = try JSON(data: raw)
        let challenge = CaptchaChallenge.from(json: json)
        XCTAssertNotNil(challenge)
        XCTAssertEqual(challenge?.field, "")
        let proof = challenge?.proof(from: "verify_token_abc")
        XCTAssertEqual(proof, "NEC:12345678:verify_token_abc")
        XCTAssertTrue(challenge?.acceptsProof(proof ?? "") == true)
    }

    func testFeedLinkResolvesNonNumericUsername() {
        XCTAssertEqual(FeedLink.resolve("/u/12202"), .user("12202"))
        XCTAssertEqual(FeedLink.resolve("/u/%E9%85%B7%E5%AE%89%E5%B0%8F%E7%BC%96"), .user("酷安小编"))
        XCTAssertEqual(FeedLink.resolve("https://www.coolapk.com/u/AsrielXuwu"), .user("AsrielXuwu"))
    }

    func testAnswerFeedParsesQuestionMetadata() throws {
        let raw = Data("""
        {
          "id": 75286597,
          "type": 11,
          "fid": 75285894,
          "uid": 20475453,
          "username": "咸鱼A310",
          "feedType": "answer",
          "message_title": "原问题标题",
          "message": "回答内容",
          "questionUrl": "/feed/75285894",
          "extraData": "{\\"questionTitle\\":\\"原问题标题\\",\\"questionUrl\\":\\"/feed/75285894\\",\\"questionAnswerNum\\":5}"
        }
        """.utf8)
        let feed = FeedItem(json: try JSON(data: raw))
        XCTAssertEqual(feed.kind, .answer)
        XCTAssertEqual(feed.effectiveFeedID, "75286597")
        XCTAssertEqual(feed.questionID, "75285894")
        XCTAssertEqual(feed.questionTitle, "原问题标题")
        XCTAssertEqual(feed.questionAnswerNum, 5)
    }
}
