import CryptoKit
import Foundation

/// Device identity and `X-App-Token` generation (v1/v2/v3) for the Coolapk API.
public enum CoolapkToken: Sendable {
    public static let defaultAPIVersion = "16"
    public static let defaultAppVersion = "16.2.0"
    public static let defaultAppCode = "2604201"
    public static let defaultSDKInt = "35"
    public static let defaultDeviceBrand = "Xiaomi"
    public static let defaultDeviceModel = "M2102J2SC"
    public static let packageName = "com.coolapk.market"

    public static func androidVersion(forSDKInt sdk: Int) -> String {
        switch sdk {
        case ...31: return "12"
        case 32: return "12L"
        case 33: return "13"
        case 34: return "14"
        case 35: return "15"
        default: return "16"
        }
    }

    public static func buildID(forSDKInt sdk: Int) -> String {
        switch sdk {
        case ...32: return "SQ3A.220705.004"
        case 33: return "TKQ1.221114.001"
        case 34: return "UKQ1.231003.002"
        case 35: return "AP3A.240905.015.A2"
        default: return "BP2A.250605.031.A2"
        }
    }

    public static func defaultUserAgent(
        deviceBrand: String = defaultDeviceBrand,
        deviceModel: String = defaultDeviceModel,
        appVersion: String = defaultAppVersion,
        appCode: String = defaultAppCode,
        sdkInt: String = defaultSDKInt
    ) -> String {
        let sdk = Int(sdkInt) ?? 35
        let androidVer = androidVersion(forSDKInt: sdk)
        let build = buildID(forSDKInt: sdk)
        return "Dalvik/2.1.0 (Linux; U; Android \(androidVer); \(deviceModel) Build/\(build)) "
            + "(#Build; \(deviceBrand); \(deviceModel); \(build); \(androidVer)) +CoolMarket/\(appVersion)-\(appCode)-universal"
    }

    // MARK: - Hashing Helpers

    public static func md5(_ input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func md5(_ input: Data) -> String {
        Insecure.MD5.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    public static func base64(_ input: String, padding: Bool) -> String {
        var encoded = Data(input.utf8).base64EncodedString()
        if !padding { encoded = encoded.replacingOccurrences(of: "=", with: "") }
        return encoded
    }

    public static func randomHex(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// Generates an `X-App-Device` value: reversed unpadded base64 of `aid; ; ; mac; brand; brand; model; build; null`.
    public static func makeDeviceCode(
        brand: String = defaultDeviceBrand,
        model: String = defaultDeviceModel,
        build: String = "AP3A.240905.015.A2"
    ) -> String {
        let aid = randomHex(8).lowercased()
        let mac = (0..<6).map { _ in String(format: "%02x", Int.random(in: 0...255)) }.joined(separator: ":")
        let raw = "\(aid); ; ; \(mac); \(brand); \(brand); \(model); \(build); null"
        return String(base64(raw, padding: false).reversed())
    }

    public static func randomDevicePreset(
        appVersion: String = defaultAppVersion,
        appCode: String = defaultAppCode
    ) -> (brand: String, model: String, sdkInt: String, buildID: String, userAgent: String, deviceCode: String) {
        let catalog: [(String, String, Int)] = [
            ("Xiaomi", "24129PN74C", 35),
            ("Xiaomi", "23116PN5BC", 34),
            ("Xiaomi", "2211133C", 33),
            ("Redmi", "23113RKC6C", 34),
            ("Redmi", "24117RK2CC", 35),
            ("OnePlus", "PJZ110", 35),
            ("OnePlus", "PJD110", 34),
            ("OPPO", "PHY110", 34),
            ("vivo", "V2324A", 34),
            ("iQOO", "V2408A", 35),
            ("HONOR", "BVLP-AN00", 35),
            ("samsung", "SM-S9280", 34),
            ("Google", "Pixel 8 Pro", 35)
        ]
        let picked = catalog.randomElement() ?? (defaultDeviceBrand, defaultDeviceModel, 35)
        let sdkString = String(picked.2)
        let build = buildID(forSDKInt: picked.2)
        let ua = defaultUserAgent(
            deviceBrand: picked.0,
            deviceModel: picked.1,
            appVersion: appVersion,
            appCode: appCode,
            sdkInt: sdkString
        )
        let code = makeDeviceCode(brand: picked.0, model: picked.1, build: build)
        return (picked.0, picked.1, sdkString, build, ua, code)
    }

    public static func createRandomNumber() -> String {
        String(Double.random(in: 0..<1)).replacingOccurrences(of: ".", with: "undefined")
    }

    // MARK: - Tokens

    public static func appTokenV1(deviceCode: String, timestamp: Int) -> String {
        let time = String(timestamp)
        let token = "token://\(packageName)/c67ef5943784d09750dcfbb31020f0ab?"
            + "\(md5(time))$\(md5(deviceCode))&\(packageName)"
        let hashed = md5(base64(token, padding: true))
        return "\(hashed)-\(deviceCode)\(String(timestamp, radix: 16))"
    }

    public static func appTokenV2(deviceCode: String, timestamp: Int) -> String? {
        let time = String(timestamp)
        let token = "token://\(packageName)/dcf01e569c1e3db93a3d0fcf191a622c?"
            + "\(md5(time))$\(md5(deviceCode))&\(packageName)"
        let base64Token = base64(token, padding: false)
        let md5Base64Token = md5(base64Token)

        let raw = "$2y$10$" + base64(time, padding: false) + "/" + md5(token)
        guard raw.count >= 29 else { return nil }
        let start = raw.index(raw.startIndex, offsetBy: 7)
        let end = raw.index(start, offsetBy: 22)
        let extracted = String(raw[start..<end])

        let canonical = BCrypt.base64Encode(Array(BCrypt.base64Decode(Array(extracted.utf8)).prefix(16)))
        guard let hash = BCrypt.hash(password: Array(md5Base64Token.utf8), salt: "$2y$10$" + canonical) else {
            return nil
        }
        return "v2" + base64(hash, padding: false)
    }

    /// Generates `X-App-Token` v3 using the embedded lookup table and cost 4 bcrypt (`$2y$04$...`).
    public static func appTokenV3(
        deviceCode: String,
        timestamp: Int,
        appCode: Int = Int(defaultAppCode) ?? 2604201
    ) -> String? {
        let table = TokenTableV3.bytes
        let md5Device = md5(deviceCode)
        for offset in 0...maxSaltProbe {
            let stamp = timestamp + offset
            guard let segment = tableSegment(for: stamp, appCode: appCode, table: table) else { return nil }
            var plain = Data("\(packageName)&".utf8)
            plain.append(segment)
            plain.append(Data("&\(md5Device)&\(stamp)&\(appCode)".utf8))

            let password = md5(plain.base64EncodedString())
            let saltSource = base64("\(String(stamp, radix: 16))/\(md5(plain))", padding: false)
            guard let salt = canonicalSalt(from: saltSource) else { continue }
            guard let hash = BCrypt.hash(password: Array(password.utf8), salt: "$2y$04$" + salt) else { continue }
            return "v3" + base64(hash, padding: false)
        }
        return nil
    }

    public static func currentToken(
        deviceCode: String,
        appCode: Int = Int(defaultAppCode) ?? 2604201,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) async -> String? {
        await Task.detached(priority: .userInitiated) {
            appTokenV3(deviceCode: deviceCode, timestamp: timestamp, appCode: appCode)
        }.value
    }

    // MARK: - v3 Helpers

    private static let maxSaltProbe = 15
    private static let standardAlphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    private static let bcryptAlphabet = Array("./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)

    private static func tableSegment(for timestamp: Int, appCode: Int, table: [UInt8]) -> Data? {
        let index = ((timestamp + appCode) % 100) * 4 + 0x80
        guard index >= 0, index + 0x80 <= table.count else { return nil }
        let chunk = String(decoding: table[index ..< index + 0x80], as: UTF8.self)
        return Data(base64Encoded: chunk)
    }

    private static func canonicalSalt(from source: String) -> String? {
        guard source.count >= 22 else { return nil }
        let head = Array(source.utf8.prefix(21))
        guard head.allSatisfy(bcryptAlphabet.contains) else { return nil }
        guard let last = source.dropFirst(21).first,
              let ascii = last.asciiValue,
              let index = standardAlphabet.firstIndex(of: ascii) else { return nil }
        let shifted = standardAlphabet[(index - 5 + standardAlphabet.count) % standardAlphabet.count]
        guard let shiftedIndex = bcryptAlphabet.firstIndex(of: shifted), shiftedIndex % 16 == 0 else { return nil }
        return String(decoding: head + [shifted], as: UTF8.self)
    }
}
