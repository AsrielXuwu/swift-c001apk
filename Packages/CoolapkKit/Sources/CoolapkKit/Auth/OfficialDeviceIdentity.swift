import Foundation

/// Parses and validates the official Coolapk `ShuzlmID` exported by tapping "复制 OAID" five times.
public enum OfficialDeviceIdentity: Sendable {
    public static let guideURL = URL(string: "https://github.com/TG-Twilight/c001apk/blob/main/docs/DEVICE_ID_IMPORT.md")!

    public enum ParseError: LocalizedError, Equatable, Sendable {
        case inputTooLong
        case missingOrAmbiguousField
        case invalidFormat

        public var errorDescription: String? {
            switch self {
            case .inputTooLong:
                return "复制内容过长，请重新从官方酷安复制"
            case .missingOrAmbiguousField:
                return "未识别到唯一的 ShuzlmID。请在官方同一页面累计点击“复制 OAID”5次，再粘贴完整内容"
            case .invalidFormat:
                return "数盟 ID 为空或格式不正确，请打开官方酷安稍等后重新复制"
            }
        }
    }

    /// Rejects malformed strings and all-zero rejection tokens.
    public static func validate(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= 4096 else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+/.=-")
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        if trimmed.unicodeScalars.allSatisfy({ $0 == "0" }) { return nil }
        return trimmed
    }

    public static func parse(_ text: String) throws -> String {
        guard text.utf16.count <= 32768 else {
            throw ParseError.inputTooLong
        }
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let pattern = try NSRegularExpression(
            pattern: #"^\s*ShuzlmID\s*[:：]\s*([^\r\n]*)$"#,
            options: [.anchorsMatchLines, .caseInsensitive]
        )
        let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        let matches = pattern.matches(in: cleaned, options: [], range: nsRange)
        guard matches.count == 1,
              let range = Range(matches[0].range(at: 1), in: cleaned) else {
            throw ParseError.missingOrAmbiguousField
        }
        let rawID = String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = rawID.lowercased()
        guard lower != "null", lower != "undefined", let valid = validate(rawID) else {
            throw ParseError.invalidFormat
        }
        return valid
    }
}
