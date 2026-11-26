import Foundation

public enum ContentFilterNormalizer: Sendable {
    public static let excludedFilterTerms = ["lsp", "手冲", "后入", "性压抑"]

    public static func normalize(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
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
        let collapsed = lower.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func visibleText(from html: String) -> String {
        var cleaned = html
            .replacingOccurrences(of: #"<(script|style|template|noscript)\b[^>]*>[\s\S]*?</\1>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<(p|div|br|li|blockquote|section|h1|h2|h3)\b[^>]*>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|li|blockquote|section|h1|h2|h3)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        cleaned = FeedHTMLParser.decodeEntities(cleaned)
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

            let utf16 = Array(sentence.utf16)
            struct Hit { let start: Int; let end: Int; let group: Int }
            var occurrences: [Hit] = []

            for (groupIndex, group) in groups.enumerated() {
                for term in group {
                    let termUTF16 = Array(term.utf16)
                    guard !termUTF16.isEmpty, termUTF16.count <= utf16.count else { continue }
                    var offset = 0
                    while offset + termUTF16.count <= utf16.count {
                        if Array(utf16[offset..<(offset + termUTF16.count)]) == termUTF16 {
                            occurrences.append(Hit(start: offset, end: offset + termUTF16.count, group: groupIndex))
                        }
                        offset += 1
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
