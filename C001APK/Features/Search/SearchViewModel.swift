import CoolapkKit
import Foundation
import Observation

public enum SearchCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "feed"
    case app = "apk"
    case game = "game"
    case topic = "feedTopic"
    case product = "product"
    case user = "user"
    case dyh = "dyh"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "动态"
        case .app: return "应用"
        case .game: return "游戏"
        case .topic: return "话题"
        case .product: return "数码"
        case .user: return "用户"
        case .dyh: return "看看号"
        }
    }
}

public enum SearchFeedFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case feed = "feed"
    case feedArticle = "feedArticle"
    case picture = "picture"
    case ershou = "ershou"
    case question = "question"
    case answer = "answer"
    case vote = "vote"
    case rating = "rating"
    case comment = "comment"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "全部"
        case .feed: return "动态"
        case .feedArticle: return "文章"
        case .picture: return "酷图"
        case .ershou: return "二手"
        case .question: return "问答"
        case .answer: return "回答"
        case .vote: return "投票"
        case .rating: return "评分"
        case .comment: return "评论"
        }
    }
}

public enum SearchSortOrder: String, CaseIterable, Identifiable, Sendable {
    case defaultOrder = "default"
    case hot = "hot"
    case dateline = "dateline"
    case reply = "reply"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .defaultOrder: return "综合"
        case .hot: return "热门"
        case .dateline: return "最新"
        case .reply: return "最新回复"
        }
    }
}

@MainActor
@Observable
public final class SearchViewModel {
    public var category: SearchCategory = .all
    public var feedFilter: SearchFeedFilter = .all
    public var sortOrder: SearchSortOrder = .defaultOrder
    public var hotWords: [String] = []
    public var hotRankingRows: [HomeFeedRow] = []
    public var isLoadingDiscovery = false
    public var suggestions: [String] = []
    public var submittedKeyword: String = ""

    public private(set) var rowsByCategory: [SearchCategory: [HomeFeedRow]] = [:]
    public private(set) var dyhResults: [DyhItem] = []
    public private(set) var searchingCategories: Set<SearchCategory> = []
    public private(set) var loadingMoreCategories: Set<SearchCategory> = []
    public private(set) var searchedQueryKeyByCategory: [SearchCategory: String] = [:]
    public private(set) var hasMoreByCategory: [SearchCategory: Bool] = [:]

    private var pageByCategory: [SearchCategory: Int] = [:]
    private var debounceTask: Task<Void, Never>?

    public init() {}

    public func currentQueryKey(for keyword: String, category target: SearchCategory) -> String {
        if target == .all {
            return "\(keyword)|\(feedFilter.rawValue)|\(sortOrder.rawValue)"
        }
        return keyword
    }

    public func loadDiscoveryIfNeeded(force: Bool = false) async {
        if !force && (!hotWords.isEmpty || !hotRankingRows.isEmpty) { return }
        isLoadingDiscovery = true
        defer { isLoadingDiscovery = false }

        if hotWords.isEmpty || force {
            hotWords = (try? await API.hotSearchWords()) ?? []
        }
        if hotRankingRows.isEmpty || force {
            let fetched = (try? await API.pageFeed(pageName: "V9_HOME_TAB_RANKING", page: 1)) ?? []
            hotRankingRows = fetched.filter { row in
                switch row {
                case .feed, .product, .topic, .app, .collection, .dyh, .event:
                    return true
                default:
                    return false
                }
            }
        }
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
            searchedQueryKeyByCategory.removeAll()
            pageByCategory.removeAll()
            hasMoreByCategory.removeAll()
            appState.settings.addSearchHistory(trimmed)
        }
        suggestions = []

        let queryKey = currentQueryKey(for: trimmed, category: activeCategory)
        if !force && searchedQueryKeyByCategory[activeCategory] == queryKey {
            return
        }

        pageByCategory[activeCategory] = 1
        hasMoreByCategory[activeCategory] = true
        searchingCategories.insert(activeCategory)
        defer {
            searchingCategories.remove(activeCategory)
        }
        let succeeded = await fetch(category: activeCategory, keyword: trimmed, page: 1, append: false, appState: appState)
        if succeeded {
            searchedQueryKeyByCategory[activeCategory] = queryKey
        }
    }

    public func loadMore(category targetCategory: SearchCategory, appState: AppState) async {
        guard !searchingCategories.contains(targetCategory),
              !loadingMoreCategories.contains(targetCategory),
              hasMoreByCategory[targetCategory] != false,
              !submittedKeyword.isEmpty else { return }
        loadingMoreCategories.insert(targetCategory)
        defer { loadingMoreCategories.remove(targetCategory) }
        let nextPage = (pageByCategory[targetCategory] ?? 1) + 1
        _ = await fetch(category: targetCategory, keyword: submittedKeyword, page: nextPage, append: true, appState: appState)
    }

    @discardableResult
    private func fetch(category targetCategory: SearchCategory, keyword: String, page: Int, append: Bool, appState: AppState) async -> Bool {
        do {
            let items = try await API.search(
                keyword: keyword,
                type: targetCategory.rawValue,
                feedType: feedFilter.rawValue,
                sort: sortOrder.rawValue,
                page: page
            )
            guard submittedKeyword == keyword else { return false }
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
            return true
        } catch {
            _ = await appState.handleAPIError(error)
            return false
        }
    }
}
