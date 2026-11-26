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

    public private(set) var rows: [HomeFeedRow] = []
    public private(set) var dyhResults: [DyhItem] = []
    public private(set) var isSearching = false
    public private(set) var isLoadingMore = false
    public private(set) var hasMore = true

    private var currentPage = 1
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

    public func submitSearch(_ keyword: String, appState: AppState) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submittedKeyword = trimmed
        appState.settings.addSearchHistory(trimmed)
        suggestions = []
        currentPage = 1
        hasMore = true
        isSearching = true
        defer { isSearching = false }
        await fetch(page: 1, append: false, appState: appState)
    }

    public func loadMore(appState: AppState) async {
        guard !isSearching, !isLoadingMore, hasMore, !submittedKeyword.isEmpty else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetch(page: currentPage + 1, append: true, appState: appState)
    }

    private func fetch(page: Int, append: Bool, appState: AppState) async {
        do {
            let items = try await API.search(keyword: submittedKeyword, type: category.rawValue, page: page)
            if category == .dyh {
                let parsed = items.map { DyhItem(json: $0) }
                if append {
                    dyhResults.append(contentsOf: parsed)
                } else {
                    dyhResults = parsed
                    rows = []
                }
                hasMore = !parsed.isEmpty
                currentPage = page
            } else {
                let parsed = API.rows(from: items)
                if append {
                    var seen = Set(rows.map(\.id))
                    let unique = parsed.filter { seen.insert($0.id).inserted }
                    rows.append(contentsOf: unique)
                    hasMore = !unique.isEmpty
                } else {
                    rows = parsed
                    dyhResults = []
                    hasMore = !parsed.isEmpty
                }
                currentPage = page
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}
