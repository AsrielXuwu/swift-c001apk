import CoolapkKit
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
public final class FeedDetailViewModel {
    public let feedID: String
    public var feed: FeedItem?
    public var replies: [ReplyItem] = []
    public var answers: [HomeFeedRow] = []
    public var sortMode: ReplySortMode = .lastUpdateDesc
    public var answerSortMode: AnswerSortMode = .defaultSort
    public var authorOnly = false
    public var isCoinRepliesExpanded = false
    public var temporarilyRevealedFilter = false
    public private(set) var repliesDeferred = false

    public private(set) var isLoadingFeed = false
    public private(set) var isRefreshingDetail = false
    public private(set) var isLoadingReplies = false
    public private(set) var isLoadingMoreReplies = false
    public private(set) var isLoadingAnswers = false
    public private(set) var isLoadingMoreAnswers = false
    public private(set) var isTogglingAuthorFollow = false
    public private(set) var hasMoreReplies = true
    public private(set) var hasMoreAnswers = true
    public private(set) var errorMessage: String?
    public private(set) var didCheckScrollDetail = false

    private var currentReplyPage = 1
    private var currentAnswerPage = 1

    public enum AnswerSortMode: String, CaseIterable, Identifiable, Sendable {
        case defaultSort = "default"
        case dateline = "dateline"
        case like = "like"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .defaultSort: return "默认排序"
            case .dateline: return "最新发布"
            case .like: return "最多点赞"
            }
        }
    }

    public enum ReplySortMode: String, CaseIterable, Identifiable, Sendable {
        case lastUpdateDesc = "lastupdate_desc"
        case datelineDesc = "dateline_desc"
        case popular = "popular"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .lastUpdateDesc: return "默认排序"
            case .datelineDesc: return "最新发布"
            case .popular: return "热门评论"
            }
        }
    }

    public init(feedID: String, initialFeed: FeedItem? = nil) {
        self.feedID = feedID
        self.feed = initialFeed
        self.isRefreshingDetail = false
    }

    public func loadAll(appState: AppState, forceRefreshDetail: Bool = false) async {
        guard !feedID.isEmpty, feedID != "0" else {
            isLoadingFeed = false
            isRefreshingDetail = false
            isLoadingReplies = false
            if feed == nil {
                errorMessage = "无效的动态 ID"
            }
            return
        }

        if !forceRefreshDetail,
           let cached = appState.cachedFeedDetail(id: feedID),
           feed == nil || appState.verifiedDetailIDs.contains(feedID) {
            feed = cached
        }

        let initialFeed = feed
        let hadInitialFeed = (initialFeed != nil)
        let alreadyVerified = !forceRefreshDetail && appState.verifiedDetailIDs.contains(feedID)
        let shouldFetchImmediately = forceRefreshDetail || initialFeed == nil
        didCheckScrollDetail = shouldFetchImmediately || alreadyVerified || (initialFeed?.needsDetailRefresh == false)
        let hasSzlm = !appState.settings.protocolParameters.szlmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        repliesDeferred = !hasSzlm && replies.isEmpty

        isLoadingFeed = !hadInitialFeed
        isRefreshingDetail = false
        isLoadingReplies = replies.isEmpty && !repliesDeferred
        errorMessage = nil
        currentReplyPage = 1
        hasMoreReplies = true

        if let initialFeed, !shouldFetchImmediately {
            appState.cacheFeedDetail(initialFeed, verified: !initialFeed.needsDetailRefresh || alreadyVerified)
            appState.historyAndFav.recordVisit(initialFeed, enabled: appState.settings.recordHistory)
            if !repliesDeferred {
                await fetchReplies(page: 1, append: false, appState: appState)
            }
            isLoadingReplies = false
            if initialFeed.kind == .question, (answers.isEmpty || forceRefreshDetail) {
                await reloadAnswers(appState: appState)
            }
            isLoadingFeed = false
            return
        }

        async let loadedFeed = fetchFeedDetail(appState: appState)
        async let initialReplies: Void = repliesDeferred
            ? ()
            : await fetchReplies(page: 1, append: false, appState: appState)

        if let loaded = await loadedFeed {
            withAnimation(.easeInOut(duration: 0.25)) {
                feed = loaded
            }
            appState.cacheFeedDetail(loaded, verified: true)
            appState.historyAndFav.recordVisit(loaded, enabled: appState.settings.recordHistory)
            if loaded.kind == .question {
                await reloadAnswers(appState: appState)
            }
        }
        isRefreshingDetail = false
        isLoadingFeed = false

        _ = await initialReplies
        isLoadingReplies = false
    }

    public func loadDeferredReplies(appState: AppState) async {
        repliesDeferred = false
        currentReplyPage = 1
        hasMoreReplies = true
        isLoadingReplies = true
        defer {
            isLoadingReplies = false
            let hasSzlm = !appState.settings.protocolParameters.szlmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if replies.isEmpty && !hasSzlm {
                repliesDeferred = true
            }
        }
        if appState.settings.protocolParameters.szlmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           appState.settings.autoAcquireSzlmOnLaunch,
           appState.settings.szlmNextAllowedAt == nil {
            _ = try? await appState.settings.acquireSzlmID()
        }
        await fetchReplies(page: 1, append: false, appState: appState)
    }

    /// Quietly checks on scroll whether a potentially truncated/collapsed feed needs updating,
    /// skipping network requests when the initial card is already complete and skipping UI updates if identical.
    public func checkDetailConsistencyOnScrollIfNeeded(appState: AppState) async {
        guard !didCheckScrollDetail, let current = feed else { return }
        didCheckScrollDetail = true
        if appState.verifiedDetailIDs.contains(feedID) { return }
        guard current.needsDetailRefresh else {
            appState.cacheFeedDetail(current, verified: true)
            return
        }
        guard let loaded = await fetchFeedDetail(appState: appState) else { return }
        guard !Self.isBodyEquivalent(current, loaded) else {
            appState.cacheFeedDetail(current, verified: true)
            return
        }

        withAnimation(.easeInOut(duration: 0.26)) {
            feed = loaded
        }
        appState.cacheFeedDetail(loaded, verified: true)
        appState.historyAndFav.recordVisit(loaded, enabled: appState.settings.recordHistory)
        if loaded.kind == .question, answers.isEmpty {
            await reloadAnswers(appState: appState)
        }
    }

    public func reloadAnswers(appState: AppState) async {
        currentAnswerPage = 1
        hasMoreAnswers = true
        isLoadingAnswers = true
        defer { isLoadingAnswers = false }
        await fetchAnswers(page: 1, append: false, appState: appState)
    }

    public func loadMoreAnswers(appState: AppState) async {
        guard !isLoadingAnswers, !isLoadingMoreAnswers, hasMoreAnswers else { return }
        isLoadingMoreAnswers = true
        defer { isLoadingMoreAnswers = false }
        await fetchAnswers(page: currentAnswerPage + 1, append: true, appState: appState)
    }

    private func fetchAnswers(page: Int, append: Bool, appState: AppState) async {
        do {
            let fetched = try await API.questionAnswers(
                id: feedID,
                page: page,
                sort: answerSortMode.rawValue
            )
            if append {
                var seen = Set(answers.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                withAnimation(.easeInOut(duration: 0.2)) {
                    answers.append(contentsOf: unique)
                }
                hasMoreAnswers = !unique.isEmpty
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    answers = fetched
                }
                hasMoreAnswers = !fetched.isEmpty
            }
            currentAnswerPage = page
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private static func isBodyEquivalent(_ lhs: FeedItem, _ rhs: FeedItem) -> Bool {
        lhs.messageTitle == rhs.messageTitle
            && lhs.message.utf16.count == rhs.message.utf16.count
            && lhs.message == rhs.message
            && lhs.articleParts.count == rhs.articleParts.count
            && lhs.mediaItems.count == rhs.mediaItems.count
            && lhs.isTruncated == rhs.isTruncated
            && (lhs.vote == nil) == (rhs.vote == nil)
            && lhs.priceText == rhs.priceText
            && lhs.dealStatusText == rhs.dealStatusText
            && lhs.extraURL == rhs.extraURL
    }

    private func fetchFeedDetail(appState: AppState) async -> FeedItem? {
        do {
            return try await API.feedDetail(id: feedID)
        } catch {
            // If we already have the feed card summary from timeline, do not block
            // the user with an extra captcha popup just for refreshing detail metadata.
            if feed != nil, case APIError.captchaRequired = error {
                return nil
            }
            let retried = await appState.handleAPIError(error)
            if retried {
                return try? await API.feedDetail(id: feedID)
            } else if feed == nil {
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    public func reloadReplies(appState: AppState) async {
        currentReplyPage = 1
        hasMoreReplies = true
        isLoadingReplies = true
        defer { isLoadingReplies = false }
        await fetchReplies(page: 1, append: false, appState: appState)
    }

    public func loadMoreReplies(appState: AppState) async {
        guard !isLoadingReplies, !isLoadingMoreReplies, hasMoreReplies else { return }
        isLoadingMoreReplies = true
        defer { isLoadingMoreReplies = false }
        await fetchReplies(page: currentReplyPage + 1, append: true, appState: appState)
    }

    private func fetchReplies(page: Int, append: Bool, appState: AppState) async {
        do {
            let fetched = try await API.replies(
                feedID: feedID,
                page: page,
                listType: sortMode.rawValue,
                authorOnly: authorOnly
            )
            if append {
                var seen = Set(replies.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                withAnimation(.easeInOut(duration: 0.2)) {
                    replies.append(contentsOf: unique)
                }
                hasMoreReplies = !unique.isEmpty
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    replies = fetched
                }
                hasMoreReplies = !fetched.isEmpty
            }
            currentReplyPage = page
        } catch {
            let retried = await appState.handleAPIError(error)
            if retried && !append {
                await fetchReplies(page: page, append: false, appState: appState)
            }
        }
    }

    public func toggleLike(appState: AppState) async {
        guard var current = feed else { return }
        guard appState.accounts.isLoggedIn else {
            appState.showLoginSheet = true
            return
        }
        let target = !current.isLiked
        current.isLiked = target
        current.likeNum = max(0, current.likeNum + (target ? 1 : -1))
        feed = current
        do {
            try await API.likeFeed(id: current.id, liked: target)
        } catch {
            current.isLiked = !target
            current.likeNum = max(0, current.likeNum + (target ? -1 : 1))
            feed = current
            _ = await appState.handleAPIError(error)
        }
    }

    public func toggleCollect(appState: AppState) async {
        guard let current = feed else { return }
        appState.favoritePickerFeed = current
    }

    public func toggleAuthorFollow(appState: AppState) async {
        guard var current = feed, !current.uid.isEmpty else { return }
        let shouldWriteCloud = appState.accounts.isLoggedIn && appState.settings.defaultFollowTarget == .cloud
        if !shouldWriteCloud {
            if appState.localFollow.contains(uid: current.uid) {
                appState.localFollow.unfollow(uid: current.uid)
                appState.showToast("已取消本机关注")
            } else {
                appState.localFollow.follow(uid: current.uid, username: current.username, avatar: current.avatar)
                appState.showToast("已加入本机关注")
            }
            return
        }
        guard !isTogglingAuthorFollow else { return }
        isTogglingAuthorFollow = true
        defer { isTogglingAuthorFollow = false }

        let target = !current.isAuthorFollowed
        current.isAuthorFollowed = target
        feed = current
        do {
            try await API.followUser(uid: current.uid, follow: target)
            if !target && appState.localFollow.contains(uid: current.uid) {
                appState.localFollow.unfollow(uid: current.uid)
            }
            appState.showToast(target ? "已同步关注至云端" : "已取消关注")
        } catch {
            current.isAuthorFollowed = !target
            feed = current
            _ = await appState.handleAPIError(error)
        }
    }

    public func toggleReplyLike(_ reply: ReplyItem, appState: AppState) async {
        guard appState.accounts.isLoggedIn else {
            appState.showLoginSheet = true
            return
        }
        guard let idx = replies.firstIndex(where: { $0.id == reply.id }) else { return }
        let target = !replies[idx].isLiked
        replies[idx].isLiked = target
        replies[idx].likeNum = max(0, replies[idx].likeNum + (target ? 1 : -1))
        do {
            try await API.likeReply(id: reply.id, liked: target)
        } catch {
            replies[idx].isLiked = !target
            replies[idx].likeNum = max(0, replies[idx].likeNum + (target ? -1 : 1))
            _ = await appState.handleAPIError(error)
        }
    }

    public func togglePinReply(_ reply: ReplyItem, appState: AppState) async {
        do {
            try await API.pinReply(feedID: feedID, replyID: reply.isTop ? nil : reply.id)
            appState.showToast(reply.isTop ? "已取消置顶" : "已置顶评论")
            await loadAll(appState: appState, forceRefreshDetail: true)
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    public func deleteReply(_ reply: ReplyItem, appState: AppState) async {
        do {
            try await API.deleteReply(id: reply.id)
            replies.removeAll { $0.id == reply.id }
            appState.showToast("已删除评论")
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    public func deleteFeed(appState: AppState) async -> Bool {
        do {
            try await API.deleteFeed(id: feedID)
            appState.showToast("已删除动态")
            return true
        } catch {
            _ = await appState.handleAPIError(error)
            return false
        }
    }
}
