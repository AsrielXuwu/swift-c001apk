import CoolapkKit
import Foundation
import Observation

public enum SearchCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "feed"
    case user = "user"
    case topic = "feedTopic"
    case app = "apk"
    case dyh = "dyh"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "动态"
        case .user: return "用户"
        case .topic: return "话题"
        case .app: return "应用"
        case .dyh: return "看看号"
        }
    }
}

@MainActor
@Observable
public final class SearchViewModel {
    public var category: SearchCategory = .all
    public var hotWords: [String] = []
    public var suggestions: [String] = []
    public var submittedKeyword: String = ""

    public private(set) var rowsByCategory: [SearchCategory: [HomeFeedRow]] = [:]
    public private(set) var dyhResults: [DyhItem] = []
    public private(set) var searchingCategories: Set<SearchCategory> = []
    public private(set) var loadingMoreCategories: Set<SearchCategory> = []
    public private(set) var searchedKeywordByCategory: [SearchCategory: String] = [:]
    public private(set) var hasMoreByCategory: [SearchCategory: Bool] = [:]

    private var pageByCategory: [SearchCategory: Int] = [:]
    private var debounceTask: Task<Void, Never>?

    public init() {}

    public func loadHotWordsIfNeeded() async {
        guard hotWords.isEmpty else { return }
        hotWords = (try? await API.hotSearchWords()) ?? []
    }

    public func updateSuggestions(for query: String) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let words = (try? await API.suggestWords(keyword: trimmed)) ?? []
            if !Task.isCancelled {
                suggestions = words
            }
        }
    }

    public func submitSearch(_ keyword: String, category targetCategory: SearchCategory? = nil, appState: AppState, force: Bool = false) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let activeCategory = targetCategory ?? category
        if submittedKeyword != trimmed {
            submittedKeyword = trimmed
            rowsByCategory.removeAll()
            dyhResults.removeAll()
            searchedKeywordByCategory.removeAll()
            pageByCategory.removeAll()
            hasMoreByCategory.removeAll()
            appState.settings.addSearchHistory(trimmed)
        }
        suggestions = []

        if !force && searchedKeywordByCategory[activeCategory] == trimmed {
            return
        }

        pageByCategory[activeCategory] = 1
        hasMoreByCategory[activeCategory] = true
        searchingCategories.insert(activeCategory)
        defer {
            searchingCategories.remove(activeCategory)
            searchedKeywordByCategory[activeCategory] = trimmed
        }
        await fetch(category: activeCategory, keyword: trimmed, page: 1, append: false, appState: appState)
    }

    public func loadMore(category targetCategory: SearchCategory, appState: AppState) async {
        guard !searchingCategories.contains(targetCategory),
              !loadingMoreCategories.contains(targetCategory),
              hasMoreByCategory[targetCategory] != false,
              !submittedKeyword.isEmpty else { return }
        loadingMoreCategories.insert(targetCategory)
        defer { loadingMoreCategories.remove(targetCategory) }
        let nextPage = (pageByCategory[targetCategory] ?? 1) + 1
        await fetch(category: targetCategory, keyword: submittedKeyword, page: nextPage, append: true, appState: appState)
    }

    private func fetch(category targetCategory: SearchCategory, keyword: String, page: Int, append: Bool, appState: AppState) async {
        do {
            let items = try await API.search(keyword: keyword, type: targetCategory.rawValue, page: page)
            guard submittedKeyword == keyword else { return }
            if targetCategory == .dyh {
                let parsed = items.map { DyhItem(json: $0) }
                if append {
                    var seen = Set(dyhResults.map(\.id))
                    let unique = parsed.filter { seen.insert($0.id).inserted }
                    dyhResults.append(contentsOf: unique)
                    hasMoreByCategory[targetCategory] = !unique.isEmpty
                } else {
                    dyhResults = parsed
                    hasMoreByCategory[targetCategory] = !parsed.isEmpty
                }
                pageByCategory[targetCategory] = page
            } else {
                let parsed = API.rows(from: items)
                if append {
                    let existing = rowsByCategory[targetCategory] ?? []
                    var seen = Set(existing.map(\.id))
                    let unique = parsed.filter { seen.insert($0.id).inserted }
                    rowsByCategory[targetCategory] = existing + unique
                    hasMoreByCategory[targetCategory] = !unique.isEmpty
                } else {
                    rowsByCategory[targetCategory] = parsed
                    hasMoreByCategory[targetCategory] = !parsed.isEmpty
                }
                pageByCategory[targetCategory] = page
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}
