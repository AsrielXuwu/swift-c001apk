import Compression
import CryptoKit
import Foundation
import Security

public struct SzlmDuidError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Field codec for the SZLM DUID protocol (`szlm_res a7b7b883`).
public enum SzlmFieldCodec: Sendable {
    public static func parameter(from timestamp: String) throws -> Int {
        guard timestamp.count >= 3 else {
            throw SzlmDuidError("时间戳参数无效")
        }
        let suffix = String(timestamp.suffix(3)).replacingOccurrences(of: ".", with: "")
        guard let value = Int(suffix) else {
            throw SzlmDuidError("时间戳参数无效")
        }
        return value
    }

    public static func encode(_ value: String, p: Int) -> String {
        let k = p % 100 % 57 + 1
        let s = value.utf16.map { Int($0 - 32 + UInt16(k)) % 95 + 32 }
        let n = s.count
        let m = n / 2
        var out: [Int] = []
        out.reserveCapacity(n)
        switch (p / 100) % 4 {
        case 0:
            if n % 2 == 1 { out.append(s[m]) }
            for i in 0..<m {
                out.append(s[n - 1 - i])
                out.append(s[m - 1 - i])
            }
        case 1:
            for i in 0..<m {
                out.append(s[n - 1 - i])
                out.append(s[i])
            }
            if n % 2 == 1 { out.append(s[m]) }
        case 2:
            var i = n - 1
            while i >= 0 { out.append(s[i]); i -= 2 }
            i = n - 2
            while i >= 0 { out.append(s[i]); i -= 2 }
        default:
            var i = 0
            while i < n { out.append(s[i]); i += 2 }
            i = 1
            while i < n { out.append(s[i]); i += 2 }
        }
        return String(decoding: out.map { UInt16($0) }, as: UTF16.self)
    }

    public static func anchor(_ value: String, p: Int) -> String {
        let chars = Array(value)
        let index = chars.count > 9 ? chars.count - 1 - (p % 10) : chars.count - 1
        let trimmed = String(chars.enumerated().compactMap { $0.offset == index ? nil : $0.element })
        return encode(trimmed, p: p)
    }

    public static func checksum(_ value: String, p: Int) -> String {
        let sum = value.utf16.reduce(0) { $0 + Int($1) } + (p % 100) / 10
        let digest = Insecure.MD5.hash(data: Data(String(sum).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .uppercased()
        return String(digest.prefix(7))
    }
}

/// Pure Swift client for explicit user-initiated SZLM DUID acquisition.
public enum SzlmDuidClient: Sendable {
    public static let host = "auni.telecome.cn"
    public static let fallbackHost = "global-auni.checktrustworthiness.com"
    public static let reportPath = "/a/mdna/report?v=8.7&t=m&p=F9BD0FBDACFE80FCF34370FBCFEE1A98"
    public static let maxResponseBytes = 64 * 1024
    private static let poolKey = Array("xp7j@&!v5]2k#+3z{n9$q^r%[8f1*d4e:c>0l?m/6)yb-=w}".utf8)

    public static func createSeed() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func buildReport(
        seed: String,
        timestamp: String,
        manufacturer: String = "Google",
        model: String = "Pixel 7",
        androidVersion: String = "13",
        sdkInt: Int = 33
    ) throws -> [String: Any] {
        guard seed.count == 32,
              seed.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else {
            throw SzlmDuidError("本机设备报文配置无法读取")
        }
        let input = String(seed.prefix(16))
        let p = try SzlmFieldCodec.parameter(from: timestamp)
        let sha1Hex = Insecure.SHA1.hash(data: Data(input.utf8))
            .map { String(format: "%02X", $0) }
            .joined()
        let chars = Array(sha1Hex)
        let mac = "\(String(chars[1..<7])):\(String(chars[13..<19])):\(String(chars[7..<13]))"
        return [
            "DUv": "com.coolapk.market",
            "75c": "11e7b222083a4b732b4b14811f6fc05995a01415eb",
            "3mS": "v9.0.1",
            "AAA": "v1.0",
            "BBB": "v1.0",
            "2cO": timestamp,
            "foO": SzlmFieldCodec.anchor(input, p: p),
            "sfOo": SzlmFieldCodec.checksum(input, p: p),
            "P1J": mac,
            "AYk": mac,
            "dLH": SzlmFieldCodec.encode(seed, p: p),
            "R37": manufacturer,
            "R3d": model,
            "R41": androidVersion,
            "SAN": sdkInt,
        ]
    }

    public static func encodeReport(_ report: [String: Any]) throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        guard var jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SzlmDuidError("无法序列化设备报文")
        }
        jsonString = jsonString.replacingOccurrences(of: "/", with: #"\/"#)
        let deflated = try zlibCompress(Data(jsonString.utf8))
        return xor(deflated)
    }

    public static func decodeID(from raw: Data) -> String? {
        guard !raw.isEmpty, raw.count <= maxResponseBytes else { return nil }
        let plain = xor(raw)
        let jsonData: Data
        if plain.count >= 2, plain[0] == 0x78, ((Int(plain[0]) << 8) + Int(plain[1])) % 31 == 0 {
            guard let decompressed = try? zlibDecompress(plain, maxOutputBytes: maxResponseBytes) else {
                return nil
            }
            jsonData = decompressed
        } else {
            jsonData = plain
        }
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        let errString = (object["err"] as? String) ?? (object["err"] as? Int).map(String.init)
        guard errString == "0" else { return nil }
        if let primary = object["n_a"] as? String, !primary.isEmpty {
            return OfficialDeviceIdentity.validate(primary)
        }
        return OfficialDeviceIdentity.validate(object["cdd"] as? String)
    }

    public static func acquire(
        seed: String? = nil,
        manufacturer: String = CoolapkToken.defaultDeviceBrand,
        model: String = CoolapkToken.defaultDeviceModel,
        androidVersion: String = "16",
        sdkInt: Int = Int(CoolapkToken.defaultSdkInt) ?? 35
    ) async throws -> String {
        let activeSeed = seed ?? createSeed()
        let ts = String(format: "%.3f", Date().timeIntervalSince1970)
        let report = try buildReport(
            seed: activeSeed,
            timestamp: ts,
            manufacturer: manufacturer,
            model: model,
            androidVersion: androidVersion,
            sdkInt: sdkInt
        )
        let payload = try encodeReport(report)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var lastError: Error?
        for targetHost in [host, fallbackHost] {
            guard let url = URL(string: "https://\(targetHost)\(reportPath)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    lastError = SzlmDuidError("数盟服务返回 HTTP \(http.statusCode)")
                    continue
                }
                if let id = decodeID(from: data) {
                    return id
                }
                lastError = SzlmDuidError("数盟服务未返回有效的设备标识")
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SzlmDuidError("数盟设备标识获取失败，请稍后重试")
    }

    // MARK: - Codec Helpers

    public static func xor(_ data: Data) -> Data {
        var result = Data(count: data.count)
        let keyCount = poolKey.count
        for i in data.indices {
            result[i] = data[i] ^ poolKey[i % keyCount]
        }
        return result
    }

    /// RFC 1950 zlib container around Apple's raw deflate `COMPRESSION_ZLIB`.
    static func zlibCompress(_ input: Data) throws -> Data {
        let source = [UInt8](input)
        let dstSize = max(64, source.count + 128)
        var dst = [UInt8](repeating: 0, count: dstSize)
        let compressedCount = source.withUnsafeBufferPointer { srcPtr in
            compression_encode_buffer(
                &dst,
                dstSize,
                srcPtr.baseAddress!,
                source.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard compressedCount > 0 else {
            throw SzlmDuidError("报文压缩失败")
        }
        var out = Data([0x78, 0x9C])
        out.append(contentsOf: dst.prefix(compressedCount))
        var checksum = adler32(source).bigEndian
        withUnsafeBytes(of: &checksum) { out.append(contentsOf: $0) }
        return out
    }

    static func zlibDecompress(_ input: Data, maxOutputBytes: Int) throws -> Data {
        guard input.count > 6 else { throw SzlmDuidError("压缩数据长度无效") }
        let flg = input[1]
        let hasPresetDict = (flg & 0x20) != 0
        let headerLen = hasPresetDict ? 6 : 2
        guard input.count > headerLen + 4 else { throw SzlmDuidError("压缩数据头部无效") }
        let deflateBytes = [UInt8](input[headerLen..<(input.count - 4)])
        var dst = [UInt8](repeating: 0, count: maxOutputBytes)
        let decodedCount = deflateBytes.withUnsafeBufferPointer { srcPtr in
            compression_decode_buffer(
                &dst,
                maxOutputBytes,
                srcPtr.baseAddress!,
                deflateBytes.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard decodedCount > 0 else {
            throw SzlmDuidError("报文解压失败")
        }
        return Data(dst.prefix(decodedCount))
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        let mod: UInt32 = 65521
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % mod
            b = (b + a) % mod
        }
        return (b << 16) | a
    }
}
