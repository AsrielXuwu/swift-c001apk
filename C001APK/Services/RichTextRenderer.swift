import CoolapkKit
import Foundation
import SwiftUI
import UIKit

@MainActor
public enum EmojiBundleStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 240
        return cache
    }()

    private static let inlineCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 240
        return cache
    }()

    public static func purgeCache() {
        cache.removeAllObjects()
        inlineCache.removeAllObjects()
    }

    public static let allNames: [String] = {
        let dir = Bundle.main.url(forResource: "Emoji", withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent("Emoji")
        guard let dir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    public static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let file = name.hasSuffix(".png") ? String(name.dropLast(4)) : name
        guard let url = Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "Emoji")
            ?? Bundle.main.url(forResource: file, withExtension: "png"),
            let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    public static func inlineImage(named name: String, pointSize: CGFloat = 20) -> UIImage? {
        let key = "\(name)|\(Int(pointSize * 10))" as NSString
        if let cached = inlineCache.object(forKey: key) { return cached }
        guard let source = image(named: name) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize))
        let rendered = renderer.image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
        }
        let aligned = rendered
            .withRenderingMode(.alwaysOriginal)
            .withBaselineOffset(fromBottom: 4)
        inlineCache.setObject(aligned, forKey: key)
        return aligned
    }

    public static func richEmojiText(
        _ raw: String,
        emojiPointSize: CGFloat = 20,
        showEmoji: Bool = true,
        enableLinks: Bool = true
    ) -> Text {
        let tokens = FeedHTMLParser.tokenize(raw)
        guard !tokens.isEmpty else { return Text("") }

        var combined = Text("")
        for token in tokens {
            switch token {
            case .newline:
                combined = Text("\(combined)\n")
            case let .emoji(name):
                if showEmoji, let emoji = inlineImage(named: name, pointSize: emojiPointSize) {
                    let imgText = Text(Image(uiImage: emoji))
                    combined = Text("\(combined)\(imgText)")
                } else {
                    combined = Text("\(combined)\(name)")
                }
            case let .text(content, bold, italic, strike, link):
                var piece: Text
                if enableLinks, let link, let resolved = resolveLinkURL(link) {
                    var attr = AttributedString(content)
                    attr.link = resolved
                    piece = Text(attr)
                } else {
                    piece = Text(content)
                }
                if bold { piece = piece.bold() }
                if italic { piece = piece.italic() }
                if strike { piece = piece.strikethrough() }
                combined = Text("\(combined)\(piece)")
            }
        }
        return combined
    }

    private static func resolveLinkURL(_ raw: String) -> URL? {
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "?&=#+"))
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed),
           let custom = URL(string: "coolapk-internal://route?target=\(encoded)") {
            return custom
        }
        return nil
    }
}

@MainActor
public enum RichTextRenderer {
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 400
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    public static func purgeCache() {
        cache.removeAllObjects()
    }

    public static func attributedString(
        html: String,
        fontSize: CGFloat,
        textColor: UIColor = .label,
        linkColor: UIColor = .tintColor,
        showEmoji: Bool = true
    ) -> NSAttributedString {
        let key = "\(Int(fontSize * 10))|\(showEmoji ? 1 : 0)|\(textColor.hash)|\(html.utf16.count)|\(html.hashValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let tokens = FeedHTMLParser.tokenize(html)
        let baseFont = UIFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 6

        let result = NSMutableAttributedString()

        for token in tokens {
            switch token {
            case .newline:
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: baseFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph
                ]))

            case let .emoji(name):
                if showEmoji, let emojiImage = EmojiBundleStore.image(named: name) {
                    let attachment = NSTextAttachment()
                    attachment.image = emojiImage
                    let size = round(fontSize * 1.25)
                    let yOffset = round((baseFont.capHeight - size) / 2)
                    attachment.bounds = CGRect(x: 0, y: yOffset, width: size, height: size)
                    let attr = NSMutableAttributedString(attachment: attachment)
                    attr.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attr.length))
                    result.append(attr)
                } else {
                    result.append(NSAttributedString(string: name, attributes: [
                        .font: baseFont,
                        .foregroundColor: textColor,
                        .paragraphStyle: paragraph
                    ]))
                }

            case let .text(text, bold, italic, strike, link):
                var traits: UIFontDescriptor.SymbolicTraits = []
                if bold { traits.insert(.traitBold) }
                if italic { traits.insert(.traitItalic) }
                let resolvedFont: UIFont
                if !traits.isEmpty, let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                    resolvedFont = UIFont(descriptor: descriptor, size: fontSize)
                } else {
                    resolvedFont = baseFont
                }

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: resolvedFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph
                ]
                if strike {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if let link, let resolvedURL = resolveLinkURL(link) {
                    attrs[.link] = resolvedURL
                    attrs[.foregroundColor] = linkColor
                }
                result.append(NSAttributedString(string: text, attributes: attrs))
            }
        }

        cache.setObject(result, forKey: key, cost: html.utf16.count * 2 + 256)
        return result
    }

    private static func resolveLinkURL(_ raw: String) -> URL? {
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "?&=#+"))
        if let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed),
           let custom = URL(string: "coolapk-internal://route?target=\(encoded)") {
            return custom
        }
        return nil
    }
}
