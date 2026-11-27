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

        if trimmed.hasPrefix("coolapk-internal://route?target="),
           let comp = URLComponents(string: trimmed),
           let target = comp.queryItems?.first(where: { $0.name == "target" })?.value,
           !target.isEmpty {
            return resolve(target)
        }

        var normalized = FeedItem.unwrapCoolapkRedirectURL(trimmed)
        if normalized.hasPrefix("coolmarket://") {
            normalized = String(normalized.dropFirst("coolmarket://".count))
        } else if normalized.hasPrefix("coolapk://") {
            normalized = String(normalized.dropFirst("coolapk://".count))
        }
        while normalized.hasPrefix("//") {
            normalized.removeFirst()
        }
        if normalized.hasPrefix("/#/") {
            normalized.removeFirst()
        }
        if !normalized.hasPrefix("/"),
           !normalized.hasPrefix("#"),
           !normalized.hasPrefix("http://"),
           !normalized.hasPrefix("https://"),
           !normalized.contains("://"),
           normalized.contains("/") || normalized.hasPrefix("page?") {
            normalized = "/" + normalized
        }
        let parsedURL = URL(string: normalized)
            ?? normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
        if let url = parsedURL, let host = url.host?.lowercased() {
            if host.contains("coolapk.com") || host.contains("coolapk1s.com") {
                if (url.path.isEmpty || url.path == "/"), let frag = url.fragment, !frag.isEmpty {
                    normalized = "#\(frag)"
                } else {
                    normalized = url.path + (url.query.map { "?\($0)" } ?? "")
                }
            } else if url.scheme == "http" || url.scheme == "https" {
                return .web(url)
            }
        }

        // Inspect entity routes whether prefixed with `/`, `/v6/`, or `#/`
        var inspectPath = normalized
        if inspectPath.hasPrefix("#/") {
            inspectPath = String(inspectPath.dropFirst(1))
        }
        if inspectPath.hasPrefix("/v6/") {
            inspectPath = "/" + String(inspectPath.dropFirst("/v6/".count))
        }

        let queryDict = parseQueryParameters(from: inspectPath)
        let pathOnly = inspectPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? inspectPath
        let lowerPath = pathOnly.lowercased()

        // Unwrap `/page?url=...` or `/page/dataList?url=...` when the inner target is a direct entity detail link
        if lowerPath == "/page" || lowerPath == "/page/datalist" || inspectPath.hasPrefix("page?"),
           let innerURL = queryDict["url"],
           !innerURL.isEmpty,
           !innerURL.uppercased().hasPrefix("V"),
           let innerResolved = resolve(innerURL) {
            if case .page = innerResolved {
                // Keep outer `/page?url=...` so title/extra query params are preserved
            } else {
                return innerResolved
            }
        }

        // 1. Topic detail links
        if let tag = extractLeadingSegment(from: pathOnly, prefix: "/t/") {
            return .topic(tag.removingPercentEncoding ?? tag)
        }
        if lowerPath == "/topic/tagdetail" || lowerPath == "/topic/newtagdetail",
           let tag = queryDict["tag"], !tag.isEmpty {
            return .topic(tag)
        }

        // 2. User space / profile links (`/u/<uid>`, `/user/<numeric_uid>`, `/user/space?uid=`, `/user/profile?uid=`, `/u?uid=`)
        // Note: In Coolapk (`TG-Twilight/c001apk` Constants.PREFIX_USER = '/u/', Constants.PREFIX_USER_LIST = '/user/'),
        // `/user/<endpoint>` paths such as `/user/dyhFollowList`, `/user/apkFollowList`, `/user/followTagList`, etc.
        // are list endpoints (not usernames!) and must route to `.page(...)`.
        let reservedUserPaths: Set<String> = [
            "user", "space", "profile", "home", "index", "login",
            "feedlist", "followlist", "fanslist", "likelist", "replylist",
            "replytomelist", "recenthistorylist", "hithistorylist",
            "dyhsubscribe", "dyhfollowlist", "apkfollowlist", "userfollowlist",
            "followtaglist", "collectionlist", "search"
        ]
        if lowerPath == "/user/space" || lowerPath == "/user/profile" || lowerPath == "/u",
           let uid = queryDict["uid"] ?? queryDict["id"],
           !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .user(uid.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let rawUser = extractLeadingSegment(from: pathOnly, prefix: "/u/") {
            let decodedUser = (rawUser.removingPercentEncoding ?? rawUser).trimmingCharacters(in: .whitespacesAndNewlines)
            if !decodedUser.isEmpty,
               !reservedUserPaths.contains(decodedUser.lowercased()),
               !decodedUser.lowercased().hasSuffix("list") {
                return .user(decodedUser)
            }
        }
        if let rawUser = extractLeadingSegment(from: pathOnly, prefix: "/user/") {
            let decodedUser = (rawUser.removingPercentEncoding ?? rawUser).trimmingCharacters(in: .whitespacesAndNewlines)
            if isNumericID(decodedUser) {
                return .user(decodedUser)
            }
        }

        // 3. Feed / Reply / Article / Picture / Answer detail links
        if lowerPath == "/feed/detail" || lowerPath == "/feed/replydetail" || lowerPath == "/feed/replylist" {
            let targetID = [queryDict["fid"], queryDict["feed_id"], queryDict["feedId"], queryDict["id"]]
                .compactMap { $0 }
                .first { isNumericID($0) && $0 != "0" }
            if let targetID {
                return .feed(targetID)
            }
        }
        for feedPrefix in ["/feed/", "/picture/", "/dyharticle/", "/answer/"] {
            if let fid = extractLeadingSegmentCaseInsensitive(from: pathOnly, prefix: feedPrefix), isNumericID(fid) {
                return .feed(fid)
            }
        }

        // 4. Product, App, Collection, Dyh, Event, Question, Vote links
        if lowerPath == "/product/detail", let pid = queryDict["id"], isNumericID(pid) {
            return .product(pid)
        }
        if let pid = extractLeadingSegment(from: pathOnly, prefix: "/product/"), isNumericID(pid) {
            return .product(pid)
        }
        if lowerPath == "/apk/detail" || lowerPath == "/game/detail",
           let aid = queryDict["id"], !aid.isEmpty {
            return .app(aid)
        }
        if let appID = extractLeadingSegment(from: pathOnly, prefix: "/apk/") ?? extractLeadingSegment(from: pathOnly, prefix: "/game/") {
            let lowerApp = appID.lowercased()
            if !["index", "list", "ranklist", "categorylist", "detail", "userfollowlist", "followlist", "commentlist"].contains(lowerApp),
               !lowerApp.hasSuffix("list") {
                return .app(appID)
            }
        }
        if lowerPath == "/collection/detail", let cid = queryDict["id"], isNumericID(cid) {
            return .collection(cid)
        }
        if let cid = extractLeadingSegment(from: pathOnly, prefix: "/collection/"), isNumericID(cid) {
            return .collection(cid)
        }
        if lowerPath == "/dyh/detail",
           let did = queryDict["dyhId"] ?? queryDict["id"], isNumericID(did) {
            return .dyh(did)
        }
        if let did = extractLeadingSegment(from: pathOnly, prefix: "/dyh/"), isNumericID(did) {
            return .dyh(did)
        }
        if lowerPath == "/event/detail", let eid = queryDict["id"], isNumericID(eid) {
            return .event(eid)
        }
        if let eid = extractLeadingSegment(from: pathOnly, prefix: "/event/"), isNumericID(eid) {
            return .event(eid)
        }
        if let qid = extractLeadingSegment(from: pathOnly, prefix: "/question/"), isNumericID(qid) {
            return .question(qid)
        }
        if let vid = extractLeadingSegment(from: pathOnly, prefix: "/vote/"), isNumericID(vid) {
            return .vote(vid)
        }

        if let url = parsedURL {
            let scheme = (url.scheme ?? "").lowercased()
            if ["http", "https", "fleamarket", "tbopen", "taobao", "alipays"].contains(scheme) {
                return .web(url)
            }
        }
        if !normalized.isEmpty && !normalized.contains("://") {
            return .page(normalized)
        }
        return nil
    }

    private static func parseQueryParameters(from path: String) -> [String: String] {
        guard let qIndex = path.firstIndex(of: "?") else { return [:] }
        let queryString = String(path[path.index(after: qIndex)...])
        var dict: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = kv.first, !rawKey.isEmpty else { continue }
            let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
            let rawVal = kv.count > 1 ? String(kv[1]) : ""
            let val = rawVal.removingPercentEncoding ?? rawVal
            if !val.isEmpty {
                dict[key] = val
            }
        }
        return dict
    }

    private static func extractLeadingSegmentCaseInsensitive(from path: String, prefix: String) -> String? {
        guard let range = path.range(of: prefix, options: [.anchored, .caseInsensitive]) else { return nil }
        var value = String(path[range.upperBound...])
        if let queryIndex = value.firstIndex(of: "?") { value = String(value[..<queryIndex]) }
        if let slashIndex = value.firstIndex(of: "/") { value = String(value[..<slashIndex]) }
        return value.isEmpty ? nil : value
    }

    private static func extractLeadingSegment(from path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        var value = String(path.dropFirst(prefix.count))
        if let queryIndex = value.firstIndex(of: "?") { value = String(value[..<queryIndex]) }
        if let slashIndex = value.firstIndex(of: "/") { value = String(value[..<slashIndex]) }
        return value.isEmpty ? nil : value
    }

    public static func inferredPageTitle(from link: String) -> String? {
        var clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean = String(clean.dropFirst()) }
        if !clean.hasPrefix("/") { clean = "/" + clean }
        guard let comps = URLComponents(string: "https://www.coolapk.com" + clean),
              let items = comps.queryItems else {
            return nil
        }
        for key in ["title", "pageTitle", "subTitle"] {
            if let val = items.first(where: { $0.name == key })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !val.isEmpty {
                return val.removingPercentEncoding ?? val
            }
        }
        if let innerURL = items.first(where: { $0.name == "url" })?.value,
           let nested = inferredPageTitle(from: innerURL) {
            return nested
        }
        return nil
    }

    private static func isNumericID(_ raw: String) -> Bool {
        !raw.isEmpty && raw.allSatisfy(\.isNumber)
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
        let out = text
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
