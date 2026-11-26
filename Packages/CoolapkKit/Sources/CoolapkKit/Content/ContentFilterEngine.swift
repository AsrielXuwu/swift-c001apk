import Foundation

private struct SendableRegex: @unchecked Sendable {
    let regex: NSRegularExpression?
    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        self.regex = try? NSRegularExpression(pattern: pattern, options: options)
    }
    func replacingMatches(in input: String, with template: String) -> String {
        guard let regex else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..<input.endIndex, in: input),
            withTemplate: template
        )
    }
}

public enum ContentFilterNormalizer: Sendable {
    public static let excludedFilterTerms = ["lsp", "手冲", "后入", "性压抑"]

    private static let scriptStyleRegex = SendableRegex(
        #"<(script|style|template|noscript)\b[^>]*>[\s\S]*?</\1>"#,
        options: [.caseInsensitive]
    )
    private static let openBlockRegex = SendableRegex(
        #"<(p|div|br|li|blockquote|section|h1|h2|h3)\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let closeBlockRegex = SendableRegex(
        #"</(p|div|li|blockquote|section|h1|h2|h3)>"#,
        options: [.caseInsensitive]
    )
    private static let anyTagRegex = SendableRegex(#"<[^>]*>"#)
    private static let whitespaceRegex = SendableRegex(#"\s+"#)

    public static func normalize(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(value.unicodeScalars.count)
        for scalar in value.unicodeScalars {
            let v = scalar.value
            if v >= 0xFF01 && v <= 0xFF5E {
                if let mapped = UnicodeScalar(v - 0xFEE0) { scalars.append(mapped) }
            } else if v == 0x3000 {
                scalars.append(" ")
            } else if (v >= 0x200B && v <= 0x200F) || (v >= 0x202A && v <= 0x202E) || v == 0x2060 || v == 0xFEFF {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        let lower = String(scalars).lowercased()
        let collapsed = whitespaceRegex.replacingMatches(in: lower, with: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func visibleText(from html: String) -> String {
        var cleaned = html
        if html.contains("<") {
            cleaned = scriptStyleRegex.replacingMatches(in: cleaned, with: "")
            cleaned = openBlockRegex.replacingMatches(in: cleaned, with: "\n")
            cleaned = closeBlockRegex.replacingMatches(in: cleaned, with: "\n")
            cleaned = anyTagRegex.replacingMatches(in: cleaned, with: "")
        }
        if cleaned.contains("&") {
            cleaned = FeedHTMLParser.decodeEntities(cleaned)
        }
        return cleaned
            .components(separatedBy: CharacterSet.newlines)
            .map { normalize($0) }
            .joined(separator: "\n")
    }
}

public struct ContentFilterEngine: Sendable {
    private struct CompiledRule: Sendable {
        let rule: FilterRule
        let groups: [[String]]
        let exceptions: [String]
    }

    private let compiledRules: [CompiledRule]

    public init(ruleSet: FilterRuleSet) {
        self.compiledRules = ruleSet.rules.map { rule in
            CompiledRule(
                rule: rule,
                groups: rule.groups.map { $0.map(ContentFilterNormalizer.normalize).filter { !$0.isEmpty } },
                exceptions: rule.exceptions.map(ContentFilterNormalizer.normalize).filter { !$0.isEmpty }
            )
        }
    }

    public func evaluate(
        _ input: FilterInput,
        level: FilterLevel = .standard,
        disabledRuleIDs: Set<String> = [],
        allowedAuthorUIDs: Set<String> = [],
        allowedContentKeys: Set<String> = []
    ) -> FilterMatch? {
        if let uid = input.authorUID, allowedAuthorUIDs.contains(uid) { return nil }
        if let key = input.contentKey, allowedContentKeys.contains(key) { return nil }

        var cachedNormalizedText: String?

        for compiled in compiledRules {
            let rule = compiled.rule
            guard rule.scopes.contains(input.scope),
                  !disabledRuleIDs.contains(rule.id) else { continue }
            if rule.kind == .text, rule.level.rank > level.rank { continue }

            let matched: Bool
            switch rule.kind {
            case .author:
                matched = input.authorUID.map { rule.values.contains($0) } ?? false
            case .topic:
                matched = rule.values.contains { input.topicIDs.contains($0) || input.topicNames.contains($0) }
            case .text:
                if cachedNormalizedText == nil {
                    cachedNormalizedText = maskExcludedTerms(ContentFilterNormalizer.visibleText(from: input.text))
                }
                matched = matchesText(cachedNormalizedText ?? "", compiled: compiled)
            }

            if matched {
                return FilterMatch(ruleID: rule.id, reason: rule.reason, kind: rule.kind)
            }
        }
        return nil
    }

    private func maskExcludedTerms(_ text: String) -> String {
        var out = text
        for term in ContentFilterNormalizer.excludedFilterTerms {
            out = out.replacingOccurrences(of: term, with: String(repeating: " ", count: term.count))
        }
        return out
    }

    private func matchesText(_ text: String, compiled: CompiledRule) -> Bool {
        let groups = compiled.groups
        guard !groups.isEmpty else { return false }
        let exceptions = compiled.exceptions
        let maxDistance = compiled.rule.maxDistance

        let separators = CharacterSet(charactersIn: "。！？!?；;\r\n")
        for sentence in text.components(separatedBy: separators) where !sentence.isEmpty {
            if exceptions.contains(where: { sentence.contains($0) }) { continue }
            if groups.contains(where: { group in !group.contains(where: { sentence.contains($0) }) }) {
                continue
            }

            struct Hit { let start: Int; let end: Int; let group: Int }
            var occurrences: [Hit] = []

            for (groupIndex, group) in groups.enumerated() {
                for term in group where !term.isEmpty {
                    var searchStart = sentence.startIndex
                    while searchStart < sentence.endIndex,
                          let found = sentence.range(of: term, range: searchStart..<sentence.endIndex) {
                        let startOffset = sentence.utf16.distance(from: sentence.startIndex, to: found.lowerBound)
                        let endOffset = sentence.utf16.distance(from: sentence.startIndex, to: found.upperBound)
                        occurrences.append(Hit(start: startOffset, end: endOffset, group: groupIndex))
                        searchStart = found.upperBound
                    }
                }
            }

            occurrences.sort { $0.end < $1.end }
            var latestStarts = [Int](repeating: -1, count: groups.count)
            for hit in occurrences {
                if hit.start > latestStarts[hit.group] {
                    latestStarts[hit.group] = hit.start
                }
                if let earliest = latestStarts.min(), earliest >= 0, hit.end - earliest <= maxDistance {
                    return true
                }
            }
        }
        return false
    }
}
