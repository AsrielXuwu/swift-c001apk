import CoolapkKit
import Foundation
import Observation

public struct SwipeFeedCard: Identifiable, Hashable, Sendable {
    public var feed: FeedItem
    public let sourceLabel: String
    public let plainSummary: String

    public var id: String { feed.id }

    public init(feed: FeedItem, sourceLabel: String) {
        self.feed = feed
        self.sourceLabel = sourceLabel
        self.plainSummary = FeedHTMLParser.plainText(feed.message).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SwipeDeckSourceMode: String, CaseIterable, Identifiable, Sendable {
    case all = "全站随机"
    case hotAndHeadline = "热门头条"
    case coolpic = "酷图精选"
    case topic = "话题精选"

    public var id: String { rawValue }
}

private enum DeckFetchSource: CaseIterable, Sendable {
    case home
    case hot
    case headline
    case coolpic
    case topicSquare
    case goods

    var label: String {
        switch self {
        case .home: return "首页动态"
        case .hot: return "热门"
        case .headline: return "头条"
        case .coolpic: return "酷图"
        case .topicSquare: return "话题"
        case .goods: return "好物"
        }
    }
}

@MainActor
@Observable
public final class SwipeDeckViewModel {
    public private(set) var cards: [SwipeFeedCard] = []
    public var currentIndex: Int = 0
    public var sourceMode: SwipeDeckSourceMode = .all
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var errorMessage: String?

    private var seenFeedIDs: Set<String> = []
    private var pageBySource: [DeckFetchSource: Int] = [:]
    private var topicPageByTag: [String: Int] = [:]
    private var discoveredTopicTags: [String] = []
    private var sessionMarker = -1
    private var likingIDs: Set<String> = []

    public init() {}

    public func syncSessionIfNeeded(appState: AppState) {
        if sessionMarker != appState.sessionVersion {
            sessionMarker = appState.sessionVersion
            resetDeckState()
        }
    }

    public func resetDeckState() {
        cards.removeAll()
        seenFeedIDs.removeAll()
        pageBySource.removeAll()
        topicPageByTag.removeAll()
        discoveredTopicTags.removeAll()
        currentIndex = 0
        errorMessage = nil
    }

    public func reload(appState: AppState, force: Bool = false) async {
        syncSessionIfNeeded(appState: appState)
        if !force, !cards.isEmpty { return }
        guard !isLoading else { return }

        if force {
            resetDeckState()
        }
        isLoading = true
        errorMessage = nil
        let expectedSession = appState.sessionVersion
        defer { isLoading = false }

        let batch = await fetchMixedBatch(appState: appState, batchSize: 4)
        guard expectedSession == appState.sessionVersion else { return }

        if batch.isEmpty && cards.isEmpty {
            errorMessage = "暂未找到带图动态，下拉或点击换一批重试"
        } else {
            appendFilteredCards(batch, appState: appState)
            prefetchAdjacentMedia(around: currentIndex)
        }
    }

    public func loadMoreIfNeeded(appState: AppState) async {
        prefetchAdjacentMedia(around: currentIndex)
        guard !isLoading, !isLoadingMore, currentIndex >= max(0, cards.count - 5) else { return }
        isLoadingMore = true
        let expectedSession = appState.sessionVersion
        defer { isLoadingMore = false }

        let batch = await fetchMixedBatch(appState: appState, batchSize: 3)
        guard expectedSession == appState.sessionVersion else { return }
        appendFilteredCards(batch, appState: appState)
    }

    public func prefetchAdjacentMedia(around index: Int) {
        let candidateIndices = [index + 1, index + 2]
        let urls = candidateIndices.compactMap { idx -> String? in
            guard cards.indices.contains(idx) else { return nil }
            return cards[idx].feed.mediaItems.first?.sourceUrl
        }.filter { !$0.isEmpty }
        guard !urls.isEmpty else { return }
        Task(priority: .utility) {
            for url in urls {
                _ = await ImagePipeline.shared.loadImage(urlString: url, maxPixelSize: 960, preferHDR: false)
            }
        }
    }

    public func toggleLike(for cardID: String, appState: AppState) async {
        guard let idx = cards.firstIndex(where: { $0.id == cardID }) else { return }
        guard appState.accounts.isLoggedIn else {
            appState.showLoginSheet = true
            return
        }
        guard !likingIDs.contains(cardID) else { return }
        likingIDs.insert(cardID)
        defer { likingIDs.remove(cardID) }

        let previousLiked = cards[idx].feed.isLiked
        let previousCount = cards[idx].feed.likeNum
        let targetLiked = !previousLiked

        cards[idx].feed.isLiked = targetLiked
        cards[idx].feed.likeNum = max(0, previousCount + (targetLiked ? 1 : -1))
        do {
            try await API.likeFeed(id: cardID, liked: targetLiked)
        } catch {
            if let currentIdx = cards.firstIndex(where: { $0.id == cardID }) {
                cards[currentIdx].feed.isLiked = previousLiked
                cards[currentIdx].feed.likeNum = previousCount
            }
            _ = await appState.handleAPIError(error)
        }
    }

    // MARK: - Private Aggregation

    private func candidateSources(for mode: SwipeDeckSourceMode) -> [DeckFetchSource] {
        switch mode {
        case .all:
            return DeckFetchSource.allCases.shuffled()
        case .hotAndHeadline:
            return [.hot, .headline, .home].shuffled()
        case .coolpic:
            return [.coolpic, .home].shuffled()
        case .topic:
            return [.topicSquare, .home, .hot].shuffled()
        }
    }

    private func fetchMixedBatch(appState: AppState, batchSize: Int) async -> [SwipeFeedCard] {
        let selectedSources = Array(candidateSources(for: sourceMode).prefix(batchSize))
        var plan: [(source: DeckFetchSource, page: Int)] = []
        for src in selectedSources {
            let nextPage = (pageBySource[src] ?? 0) + 1
            pageBySource[src] = nextPage
            plan.append((src, nextPage))
        }

        let extraTopicTag = pickRandomTopicTag()
        let extraTopicPage: Int? = extraTopicTag.map { tag in
            let next = (topicPageByTag[tag] ?? 0) + 1
            topicPageByTag[tag] = next
            return next
        }

        let rawCollected: [SwipeFeedCard] = await withTaskGroup(of: [SwipeFeedCard].self) { group in
            for item in plan {
                group.addTask {
                    await Self.fetchFromSource(item.source, page: item.page)
                }
            }
            if let extraTopicTag, let extraTopicPage, sourceMode == .all || sourceMode == .topic {
                group.addTask {
                    let rows = (try? await API.topicFeeds(tag: extraTopicTag, page: extraTopicPage)) ?? []
                    return Self.extractMediaFeeds(from: rows, sourceLabel: TopicItem.cleanTitle(extraTopicTag))
                }
            }

            var buckets: [[SwipeFeedCard]] = []
            for await cards in group where !cards.isEmpty {
                buckets.append(cards)
            }

            // Interleave buckets round-robin so every swipe alternates topics & boards.
            var interleaved: [SwipeFeedCard] = []
            let maxCount = buckets.map(\.count).max() ?? 0
            for offset in 0..<maxCount {
                for bucket in buckets where offset < bucket.count {
                    interleaved.append(bucket[offset])
                }
            }
            return interleaved
        }

        return rawCollected
    }

    private func appendFilteredCards(_ incoming: [SwipeFeedCard], appState: AppState) {
        var added: [SwipeFeedCard] = []
        for card in incoming {
            let feed = card.feed
            let canonicalID = feed.effectiveFeedID.isEmpty ? feed.id : feed.effectiveFeedID
            guard !canonicalID.isEmpty,
                  feed.mediaItems.contains(where: { !$0.sourceUrl.isEmpty }),
                  appState.blacklist.isUserBlocked(feed.uid) == false,
                  appState.contentFilter.match(feed: feed) == nil,
                  seenFeedIDs.insert(canonicalID).inserted else {
                continue
            }
            added.append(card)
            collectTopicTags(from: feed)
        }
        cards.append(contentsOf: added.shuffled())
    }

    private func collectTopicTags(from feed: FeedItem) {
        let candidates = feed.relationEntities.map(\.title) + feed.topicTags
        for raw in candidates {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, !discoveredTopicTags.contains(cleaned), discoveredTopicTags.count < 40 {
                discoveredTopicTags.append(cleaned)
            }
        }
    }

    private func pickRandomTopicTag() -> String? {
        guard !discoveredTopicTags.isEmpty else { return nil }
        return discoveredTopicTags.randomElement()
    }

    private nonisolated static func fetchFromSource(_ source: DeckFetchSource, page: Int) async -> [SwipeFeedCard] {
        do {
            let rows: [HomeFeedRow]
            switch source {
            case .home:
                rows = try await API.homeFeed(page: page)
            case .hot:
                rows = try await API.pageFeed(pageName: "V9_HOME_TAB_RANKING", page: page)
            case .headline:
                rows = try await API.headlineFeed(page: page)
            case .coolpic:
                let primary = (try? await API.coolPic(tag: "全部", type: "recommend", page: page)) ?? []
                rows = primary.isEmpty
                    ? (try await API.pageFeed(pageName: "V11_FIND_COOLPIC", page: page))
                    : primary
            case .topicSquare:
                if page == 1, let tabs = try? await API.topicVerticalTabs(), let picked = tabs.randomElement(), !picked.url.isEmpty {
                    rows = (try? await API.linkFeed(link: picked.url, page: 1)) ?? []
                } else {
                    rows = try await API.pageFeed(pageName: "V11_VERTICAL_TOPIC", page: page)
                }
            case .goods:
                rows = try await API.pageFeed(pageName: "V11_FIND_GOODS", page: page)
            }
            return extractMediaFeeds(from: rows, sourceLabel: source.label)
        } catch {
            return []
        }
    }

    private nonisolated static func extractMediaFeeds(from rows: [HomeFeedRow], sourceLabel: String) -> [SwipeFeedCard] {
        var extracted: [SwipeFeedCard] = []
        for row in rows {
            if case let .feed(feed) = row,
               feed.mediaItems.contains(where: { !$0.sourceUrl.isEmpty }) {
                let resolvedTag = !feed.targetTitle.isEmpty ? feed.targetTitle : sourceLabel
                extracted.append(SwipeFeedCard(feed: feed, sourceLabel: resolvedTag))
            }
        }
        return extracted.shuffled()
    }
}
