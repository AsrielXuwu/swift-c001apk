import Foundation

public enum FeedLink: Hashable, Sendable {
    case topic(String)
    case user(String)
    case feed(String)
    case product(String)
    case app(String)
    case collection(String)
    case dyh(String)
    case question(String)
    case vote(String)
    case event(String)
    case page(String)
    case web(URL)

    public static func resolve(_ raw: String) -> FeedLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var normalized = trimmed
        if normalized.hasPrefix("coolmarket://") {
            normalized = "/" + String(normalized.dropFirst("coolmarket://".count))
        }
        if let url = URL(string: normalized), let host = url.host?.lowercased() {
            if host.contains("coolapk.com") || host.contains("coolapk1s.com") {
                normalized = url.path + (url.query.map { "?\($0)" } ?? "")
            } else if url.scheme == "http" || url.scheme == "https" {
                return .web(url)
            }
        }

        if normalized.hasPrefix("/page?url=") || normalized.hasPrefix("#/") {
            return .page(normalized)
        }
        if let tag = extractSegment(from: normalized, prefix: "/t/") {
            return .topic(tag.removingPercentEncoding ?? tag)
        }
        if let uid = extractSegment(from: normalized, prefix: "/u/") {
            return .user(uid)
        }
        if let fid = extractSegment(from: normalized, prefix: "/feed/") {
            return .feed(fid)
        }
        if let pid = extractSegment(from: normalized, prefix: "/product/") {
            return .product(pid)
        }
        if let appID = extractSegment(from: normalized, prefix: "/apk/") ?? extractSegment(from: normalized, prefix: "/game/") {
            return .app(appID)
        }
        if let cid = extractSegment(from: normalized, prefix: "/collection/") {
            return .collection(cid)
        }
        if let did = extractSegment(from: normalized, prefix: "/dyh/") {
            return .dyh(did)
        }
        if let eid = extractSegment(from: normalized, prefix: "/event/") {
            return .event(eid)
        }
        if let qid = extractSegment(from: normalized, prefix: "/question/") {
            return .question(qid)
        }
        if let vid = extractSegment(from: normalized, prefix: "/vote/") {
            return .vote(vid)
        }
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return .web(url)
        }
        return nil
    }

    private static func extractSegment(from path: String, prefix: String) -> String? {
        guard let range = path.range(of: prefix) else { return nil }
        var value = String(path[range.upperBound...])
        if let queryIndex = value.firstIndex(of: "?") { value = String(value[..<queryIndex]) }
        if let slashIndex = value.firstIndex(of: "/") { value = String(value[..<slashIndex]) }
        return value.isEmpty ? nil : value
    }
}

public enum RichTextToken: Hashable, Sendable {
    case text(String, bold: Bool, italic: Bool, strike: Bool, link: String?)
    case emoji(name: String)
    case newline
}

/// Platform-independent HTML parser for Coolapk dynamic/comment messages.
public enum FeedHTMLParser: Sendable {
    public static func tokenize(_ html: String) -> [RichTextToken] {
        var tokens: [RichTextToken] = []
        var boldDepth = 0
        var italicDepth = 0
        var strikeDepth = 0
        var linkURL: String?
        var index = html.startIndex

        func appendText(_ raw: String) {
            let decoded = decodeEntities(raw)
            guard !decoded.isEmpty else { return }
            tokens.append(.text(
                decoded,
                bold: boldDepth > 0,
                italic: italicDepth > 0,
                strike: strikeDepth > 0,
                link: linkURL
            ))
        }

        while index < html.endIndex {
            let ch = html[index]
            if ch == "<" {
                guard let close = html[index...].firstIndex(of: ">") else {
                    appendText(String(html[index...]))
                    break
                }
                let rawTag = String(html[html.index(after: index)..<close])
                index = html.index(after: close)
                let needsNewline = apply(
                    tag: rawTag.lowercased(),
                    original: rawTag,
                    boldDepth: &boldDepth,
                    italicDepth: &italicDepth,
                    strikeDepth: &strikeDepth,
                    linkURL: &linkURL
                )
                if needsNewline { tokens.append(.newline) }
                continue
            }

            if ch == "[" {
                if let close = html[index...].firstIndex(of: "]"),
                   html.distance(from: index, to: close) <= 20 {
                    let name = String(html[index...close])
                    if name.count >= 3 && !name.contains("\n") && !name.contains("<") {
                        tokens.append(.emoji(name: name))
                        index = html.index(after: close)
                        continue
                    }
                }
            }

            var end = html.index(after: index)
            while end < html.endIndex, html[end] != "<", html[end] != "[" {
                end = html.index(after: end)
            }
            appendText(String(html[index..<end]))
            index = end
        }
        return tokens
    }

    public static func plainText(_ html: String) -> String {
        var output = ""
        for token in tokenize(html) {
            switch token {
            case let .text(str, _, _, _, _): output += str
            case let .emoji(name): output += name
            case .newline: output += "\n"
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isCoinOnlyReply(message: String, pics: [String]) -> Bool {
        guard pics.allSatisfy({ $0.isEmpty }) else { return false }
        let tokens = tokenize(message)
        var hasCoinEmoji = false
        for token in tokens {
            switch token {
            case .newline:
                continue
            case let .emoji(name):
                if name.contains("酷币") || name == "[新币1分]" {
                    hasCoinEmoji = true
                } else {
                    return false
                }
            case let .text(str, _, _, _, _):
                if !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return false
                }
            }
        }
        return hasCoinEmoji
    }

    private static func apply(
        tag: String,
        original: String,
        boldDepth: inout Int,
        italicDepth: inout Int,
        strikeDepth: inout Int,
        linkURL: inout String?
    ) -> Bool {
        let name = tag.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? tag
        switch name {
        case "b", "strong":
            boldDepth += 1
        case "/b", "/strong":
            boldDepth = max(0, boldDepth - 1)
        case "i", "em":
            italicDepth += 1
        case "/i", "/em":
            italicDepth = max(0, italicDepth - 1)
        case "s", "del", "strike":
            strikeDepth += 1
        case "/s", "/del", "/strike":
            strikeDepth = max(0, strikeDepth - 1)
        case "a":
            linkURL = extractHref(from: original)
        case "/a":
            linkURL = nil
        case "br", "br/", "/p", "/div", "/li", "/blockquote":
            return true
        default:
            break
        }
        return false
    }

    private static func extractHref(from tag: String) -> String? {
        for quote in ["\"", "'"] {
            if let range = tag.range(of: "href=\(quote)", options: .caseInsensitive) {
                let tail = tag[range.upperBound...]
                if let end = tail.firstIndex(of: Character(quote)) {
                    return decodeEntities(String(tail[..<end]))
                }
            }
        }
        return nil
    }

    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
        return out
    }
}
