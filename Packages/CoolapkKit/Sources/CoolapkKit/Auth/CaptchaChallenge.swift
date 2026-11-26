import Foundation

/// Captcha challenge extracted from Coolapk `err_request_captcha_v2` responses.
public struct CaptchaChallenge: Equatable, Hashable, Sendable {
    public static let defaultID = "414e5c9b866a03db03f860a1a9101672"

    public let captchaID: String
    public let field: String

    public init(captchaID: String, field: String) {
        self.captchaID = captchaID
        self.field = field
    }

    public static func from(json: JSON) -> CaptchaChallenge? {
        guard json.messageStatus.string == "err_request_captcha_v2" else { return nil }
        var extra = json.messageExtra.isNull ? json.extra : json.messageExtra
        if !extra.isNull, !extra.isObject {
            let parsed = extra.parsed
            if !parsed.isNull { extra = parsed }
        }
        if !extra.isObject { extra = json }

        let rawID = extra.captchaId.string
        let validID = rawID.count >= 16 && rawID.count <= 64 && rawID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let captchaID = validID ? rawID : defaultID

        let rawField = extra.captchaField.optionalString
        let resolvedField: String
        if let rawField {
            let trimmed = rawField.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                resolvedField = ""
            } else if trimmed.hasPrefix("_"),
                      trimmed.count >= 2,
                      trimmed.count <= 64,
                      trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
                resolvedField = trimmed
            } else {
                resolvedField = "_v2_post_token"
            }
        } else {
            resolvedField = "_v2_post_token"
        }

        return CaptchaChallenge(captchaID: captchaID, field: resolvedField)
    }

    public func proof(from validate: String) -> String? {
        guard !validate.isEmpty, validate.count <= 8192 else { return nil }
        let hasControlOrSpace = validate.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 0x20
        }
        guard !hasControlOrSpace else { return nil }
        return "NEC:\(captchaID.prefix(8)):\(validate)"
    }

    public func acceptsProof(_ proof: String) -> Bool {
        proof.hasPrefix("NEC:\(captchaID.prefix(8)):")
            && proof.count > 13
            && proof.count <= 8205
            && !proof.unicodeScalars.contains {
                CharacterSet.whitespacesAndNewlines.contains($0) || $0.value < 0x20
            }
    }
}
