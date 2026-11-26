import CoolapkKit
import Foundation
import UIKit

public enum ExportFormat: String, Sendable {
    case markdown
    case html

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        }
    }
}

public struct PreparedExportResult: Sendable {
    public let fileURL: URL
    public let warnings: [String]
}

@MainActor
public enum ExportCoordinator {
    private static let maxImageBytes = 8 * 1024 * 1024
    private static let maxTotalBytes = 32 * 1024 * 1024
    private static let maxImages = 60

    public static func prepareExport(
        feed: FeedItem,
        format: ExportFormat,
        filterService: ContentFilterService,
        blockedUIDs: Set<String>
    ) async throws -> PreparedExportResult {
        var warnings: [String] = []
        var notices: [String] = []
        var popular: [ReplyItem] = []

        do {
            popular = try await API.hotReplies(feedID: feed.id, page: 1)
        } catch {
            notices.append("未能取得热门评论；可返回评论区完成验证后重试。本文件仅含已取得的置顶评论。")
            warnings.append("热门评论读取失败，本次无法保证保存前三条评论。")
        }

        let pinnedFiltered = feed.topReplyRows.filter { filterService.match(reply: $0) == nil }
        let popularFiltered = popular.filter { filterService.match(reply: $0) == nil }
        let selectedComments = ExportDocument.selectExportComments(
            pinned: pinnedFiltered,
            popular: popularFiltered,
            blockedUIDs: blockedUIDs
        )

        if format == .markdown {
            let previewDoc = ExportDocument.fromFeed(feed, comments: selectedComments, notices: notices)
            if !previewDoc.imageURLs.isEmpty {
                notices.append("Markdown 图片保留在线链接，离线阅读图片请另存为 HTML。")
            }
            let doc = ExportDocument.fromFeed(feed, comments: selectedComments, notices: notices)
            let url = try writeTempFile(name: "\(doc.fileName).md", data: Data(doc.markdown.utf8))
            return PreparedExportResult(fileURL: url, warnings: warnings)
        }

        let doc = ExportDocument.fromFeed(feed, comments: selectedComments, notices: notices)
        var embedded: [String: String] = [:]
        var totalUsed = 0
        let deadline = Date().addingTimeInterval(45)

        for url in doc.imageURLs.prefix(maxImages) {
            if Date() > deadline || totalUsed >= maxTotalBytes { break }
            guard let data = await ImagePipeline.shared.fetchRawData(urlString: url, maxBytes: maxImageBytes),
                  data.count <= maxImageBytes,
                  totalUsed + data.count <= maxTotalBytes,
                  let mime = detectMIME(data),
                  UIImage(data: data) != nil else {
                continue
            }
            totalUsed += data.count
            embedded[url] = "data:\(mime);base64,\(data.base64EncodedString())"
        }

        let missing = doc.imageURLs.count - embedded.count
        if missing > 0 {
            warnings.append("\(missing) 张图片未能保存，将以来源链接代替；这些图片无法离线查看。")
        }

        let html = doc.offlineHTML(embeddedImages: embedded)
        let url = try writeTempFile(name: "\(doc.fileName).html", data: Data(html.utf8))
        return PreparedExportResult(fileURL: url, warnings: warnings)
    }

    private static func writeTempFile(name: String, data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func detectMIME(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 8, bytes[0...7] == [137, 80, 78, 71, 13, 10, 26, 10] { return "image/png" }
        if bytes.count >= 3, bytes[0...2] == [255, 216, 255] { return "image/jpeg" }
        if bytes.count >= 6, bytes[0...2] == [71, 73, 70] { return "image/gif" }
        if bytes.count >= 12,
           String(bytes: bytes[0...3], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8...11], encoding: .ascii) == "WEBP" {
            return "image/webp"
        }
        return nil
    }
}
