import Foundation

public struct ExportDocument: Sendable {
    public let title: String
    public let feedID: String
    public let imageURLs: [String]
    public let fileName: String
    private let htmlBody: String
    private let markdownBody: String

    public static func selectExportComments(
        pinned: [ReplyItem],
        popular: [ReplyItem],
        blockedUIDs: Set<String>
    ) -> [ReplyItem] {
        var seen: Set<String> = []
        var result: [ReplyItem] = []
        let candidates = pinned + popular.filter { $0.isTop } + popular
        for reply in candidates {
            guard !reply.id.isEmpty,
                  !blockedUIDs.contains(reply.uid),
                  seen.insert(reply.id).inserted else { continue }
            var copy = reply
            if pinned.contains(where: { $0.id == reply.id }) {
                copy.isTop = true
            }
            result.append(copy)
            if result.count == 3 { break }
        }
        return result
    }

    public static func fromFeed(
        _ feed: FeedItem,
        comments: [ReplyItem] = [],
        notices: [String] = []
    ) -> ExportDocument {
        let id = feed.id
        let rawTitle = FeedHTMLParser.plainText(feed.messageTitle)
        let altTitle = FeedHTMLParser.plainText(feed.title)
        let title = !rawTitle.isEmpty ? rawTitle : (!altTitle.isEmpty ? altTitle : "\(feed.username.isEmpty ? "未知作者" : feed.username)的动态")

        var html = "<h1>\(escapeHTML(title))</h1>"
        html += metadataHTML(username: feed.username, date: feed.dateline)
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        html += """
        <p><a href="https://www.coolapk.com/feed/\(encodedID)">https://www.coolapk.com/feed/\(encodedID)</a><br>
        <a href="https://www.coolapk1s.com/feed/\(encodedID)">https://www.coolapk1s.com/feed/\(encodedID)</a></p>
        """

        var md = "# \(title)\n\n"
        md += "- 作者：\(feed.username.isEmpty ? "未知作者" : feed.username)\n"
        if let date = feed.dateline {
            md += "- 发布时间：\(formatDate(date))\n"
        }
        md += "- 原文链接：https://www.coolapk.com/feed/\(encodedID)\n"
        md += "- 镜像链接：https://www.coolapk1s.com/feed/\(encodedID)\n\n"

        var urls: [String] = []
        var seenURLs: Set<String> = []
        func recordImage(_ url: String) {
            let normalized = coolapkNormalizedURL(url)
            guard !normalized.isEmpty, seenURLs.insert(normalized).inserted else { return }
            urls.append(normalized)
        }

        if !feed.articleParts.isEmpty {
            if !feed.cover.isEmpty {
                recordImage(feed.cover)
                html += figureHTML(url: feed.cover, caption: "")
                md += "![](\(feed.cover))\n\n"
            }
            for part in feed.articleParts {
                switch part.type {
                case "title":
                    if !part.title.isEmpty {
                        let plain = FeedHTMLParser.plainText(part.title)
                        html += "<h2>\(escapeHTML(plain))</h2>"
                        md += "## \(plain)\n\n"
                    }
                case "text":
                    let plain = FeedHTMLParser.plainText(part.message)
                    if !plain.isEmpty {
                        html += "<p>\(escapeHTML(plain).replacingOccurrences(of: "\n", with: "<br>"))</p>"
                        md += "\(plain)\n\n"
                    }
                case "image":
                    if !part.url.isEmpty {
                        recordImage(part.url)
                        html += figureHTML(url: part.url, caption: part.description)
                        md += "![\(part.description)](\(part.url))\n\n"
                    }
                case "shareUrl":
                    if !part.url.isEmpty {
                        let label = part.title.isEmpty ? part.url : part.title
                        html += "<p><a href=\"\(escapeHTML(part.url))\">\(escapeHTML(label))</a></p>"
                        md += "[\(label)](\(part.url))\n\n"
                    }
                default:
                    break
                }
            }
        } else {
            let bodyPlain = FeedHTMLParser.plainText(feed.message)
            if !bodyPlain.isEmpty {
                html += "<p>\(escapeHTML(bodyPlain).replacingOccurrences(of: "\n", with: "<br>"))</p>"
                md += "\(bodyPlain)\n\n"
            }
            for pic in feed.pics {
                recordImage(pic)
                html += figureHTML(url: pic, caption: "")
                md += "![](\(pic))\n\n"
            }
        }

        if let forward = feed.sourceFeed {
            let forwardAuthor = forward.username.isEmpty ? "未知作者" : forward.username
            let forwardText = FeedHTMLParser.plainText(forward.message)
            html += "<blockquote><p>转发自：\(escapeHTML(forwardAuthor))</p>"
            if !forwardText.isEmpty {
                html += "<p>\(escapeHTML(forwardText).replacingOccurrences(of: "\n", with: "<br>"))</p>"
            }
            for pic in forward.pics {
                recordImage(pic)
                html += figureHTML(url: pic, caption: "")
            }
            html += "</blockquote>"

            md += "> 转发自：\(forwardAuthor)\n"
            if !forwardText.isEmpty {
                for line in forwardText.components(separatedBy: "\n") {
                    md += "> \(line)\n"
                }
            }
            for pic in forward.pics {
                md += "> ![](\(pic))\n"
            }
            md += "\n"
        }

        if !comments.isEmpty {
            html += "<hr><h2>精选评论（置顶优先，其余按热门排序）</h2>"
            md += "---\n\n## 精选评论（置顶优先，其余按热门排序）\n\n"
            for reply in comments.prefix(3) {
                let author = reply.username.isEmpty ? "未知用户" : reply.username
                let badge = reply.isTop ? "【置顶】" : ""
                let text = FeedHTMLParser.plainText(reply.message)
                html += "<section><h3>\(badge)\(escapeHTML(author))</h3>"
                html += metadataHTML(username: author, date: reply.dateline)
                html += "<p>赞：\(reply.likeNum)</p>"
                if !text.isEmpty {
                    html += "<p>\(escapeHTML(text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
                }
                for pic in reply.pics {
                    recordImage(pic)
                    html += figureHTML(url: pic, caption: "")
                }
                html += "</section>"

                md += "### \(badge)\(author)（赞 \(reply.likeNum)）\n"
                if !text.isEmpty { md += "\(text)\n\n" }
                for pic in reply.pics { md += "![](\(pic))\n\n" }
            }
        }

        for notice in notices {
            html += "<p>保存说明：\(escapeHTML(notice))</p>"
            md += "_保存说明：\(notice)_\n\n"
        }

        let safeName = sanitizedFileName(title: title, id: id)
        return ExportDocument(
            title: title,
            feedID: id,
            imageURLs: urls,
            fileName: safeName,
            htmlBody: html,
            markdownBody: md.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        )
    }

    public var markdown: String { markdownBody }

    public func offlineHTML(embeddedImages: [String: String]) -> String {
        var rendered = htmlBody
        for url in imageURLs {
            let escaped = Self.escapeHTML(url)
            let token = "<img src=\"\(escaped)\""
            if let dataURI = embeddedImages[url],
               dataURI.hasPrefix("data:image/png;base64,") ||
               dataURI.hasPrefix("data:image/jpeg;base64,") ||
               dataURI.hasPrefix("data:image/gif;base64,") ||
               dataURI.hasPrefix("data:image/webp;base64,") {
                rendered = rendered.replacingOccurrences(of: token, with: "<img src=\"\(dataURI)\"")
            } else {
                let fallback = "<a href=\"\(escaped)\">图片未保存：查看来源</a>"
                rendered = rendered.replacingOccurrences(
                    of: "\(token) alt=\"\"",
                    with: fallback
                )
            }
        }
        return wrapPage(body: rendered)
    }

    private func wrapPage(body: String) -> String {
        """
        <!doctype html><html lang="zh-CN"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>\(Self.escapeHTML(title))</title>
        <style>
        body{max-width:840px;margin:32px auto;padding:0 20px;color:#202124;background:#fff;font:16px/1.7 -apple-system,system-ui,sans-serif;overflow-wrap:anywhere}
        img{max-width:100%;height:auto;border-radius:8px}a{color:#0fb860}blockquote{border-left:4px solid #bbb;padding-left:16px;margin-left:0;color:#555}
        figcaption{color:#555;font-size:14px}section{border-bottom:1px solid #ddd;padding-bottom:16px}
        @media (prefers-color-scheme:dark){body{color:#e8eaed;background:#121212}blockquote,figcaption{color:#aaa}section{border-color:#333}}
        </style></head><body>\(body)</body></html>
        """
    }

    public static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func figureHTML(url: String, caption: String) -> String {
        let normalized = coolapkNormalizedURL(url)
        let capHTML = caption.isEmpty ? "" : "<figcaption>\(escapeHTML(caption))</figcaption>"
        return "<figure><img src=\"\(escapeHTML(normalized))\" alt=\"\(escapeHTML(caption))\">\(capHTML)</figure>"
    }

    private static func metadataHTML(username: String, date: Date?) -> String {
        let author = username.isEmpty ? "未知作者" : username
        let dateText = date.map { "<br>发布时间：\(formatDate($0))" } ?? ""
        return "<p>作者：\(escapeHTML(author))\(dateText)</p>"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func sanitizedFileName(title: String, id: String) -> String {
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*")
        let cleaned = String(title.unicodeScalars.map { invalid.contains($0) || $0.value < 0x20 ? "_" : Character($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n\r"))
        var prefix = String(cleaned.prefix(70))
        if prefix.isEmpty { prefix = "动态" }
        let safeID = String(id.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") ? $0 : "_" })
        return "\(prefix)-\(safeID)"
    }
}
