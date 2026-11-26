import CoolapkKit
import Foundation
import Observation

@MainActor
@Observable
public final class FeedDetailViewModel {
    public let feedID: String
    public var feed: FeedItem?
    public var replies: [ReplyItem] = []
    public var answers: [HomeFeedRow] = []
    public var sortMode: ReplySortMode = .lastUpdateDesc
    public var authorOnly = false
    public var isCoinRepliesExpanded = false
    public var temporarilyRevealedFilter = false

    public private(set) var isLoadingFeed = false
    public private(set) var isRefreshingDetail = false
    public private(set) var isLoadingReplies = false
    public private(set) var isLoadingMoreReplies = false
    public private(set) var isTogglingAuthorFollow = false
    public private(set) var hasMoreReplies = true
    public private(set) var errorMessage: String?

    private var currentReplyPage = 1

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
        self.isRefreshingDetail = (initialFeed?.needsDetailRefresh == true)
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

        let initialFeed = feed
        let hadInitialFeed = (initialFeed != nil)
        let shouldFetchDetail = forceRefreshDetail || initialFeed == nil || (initialFeed?.needsDetailRefresh == true)

        isLoadingFeed = !hadInitialFeed
        isRefreshingDetail = shouldFetchDetail && hadInitialFeed
        isLoadingReplies = replies.isEmpty
        errorMessage = nil
        currentReplyPage = 1
        hasMoreReplies = true

        if let initialFeed, !shouldFetchDetail {
            appState.historyAndFav.recordVisit(initialFeed, enabled: appState.settings.recordHistory)
            await fetchReplies(page: 1, append: false, appState: appState)
            isLoadingReplies = false
            if initialFeed.kind == .question, answers.isEmpty {
                answers = (try? await API.questionAnswers(id: feedID, page: 1)) ?? []
            }
            isRefreshingDetail = false
            isLoadingFeed = false
            return
        }

        if let loaded = await fetchFeedDetail(appState: appState) {
            feed = loaded
            appState.historyAndFav.recordVisit(loaded, enabled: appState.settings.recordHistory)
            if loaded.kind == .question {
                answers = (try? await API.questionAnswers(id: feedID, page: 1)) ?? []
            }
        }
        isRefreshingDetail = false
        isLoadingFeed = false

        await fetchReplies(page: 1, append: false, appState: appState)
        isLoadingReplies = false
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
                replies.append(contentsOf: unique)
                hasMoreReplies = !unique.isEmpty
            } else {
                replies = fetched
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
