import CoolapkKit
import Foundation
import Observation

public enum MessagesSegment: String, CaseIterable, Identifiable, Sendable {
    case chat = "私信"
    case reply = "回复"
    case atMe = "@我"
    case likes = "赞"
    case follow = "粉丝"
    case system = "通知"

    public var id: String { rawValue }

    var notificationEndpointType: String {
        switch self {
        case .chat: return ""
        case .reply: return "commentMe"
        case .atMe: return "atMe"
        case .likes: return "feedLike"
        case .follow: return "contactsFollow"
        case .system: return "list"
        }
    }
}

@MainActor
@Observable
public final class MessagesViewModel {
    public var segment: MessagesSegment = .chat
    public private(set) var threads: [MessageThread] = []
    public private(set) var notifications: [NotificationItem] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var hasMore = true
    public private(set) var errorMessage: String?

    private var currentPage = 1
    private var sessionMarker = -1

    public init() {}

    public func syncSessionIfNeeded(appState: AppState) {
        if sessionMarker != appState.sessionVersion {
            sessionMarker = appState.sessionVersion
            threads = []
            notifications = []
            currentPage = 1
            hasMore = true
            errorMessage = nil
        }
    }

    public func loadInitial(appState: AppState, force: Bool = false) async {
        syncSessionIfNeeded(appState: appState)
        guard appState.accounts.isLoggedIn else {
            threads = []
            notifications = []
            return
        }
        if !force && (!threads.isEmpty || !notifications.isEmpty) { return }
        currentPage = 1
        hasMore = true
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        await fetch(page: 1, append: false, appState: appState)
        await appState.refreshBadgeOnly()
    }

    public func loadMore(appState: AppState) async {
        guard !isLoading, !isLoadingMore, hasMore, appState.accounts.isLoggedIn else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetch(page: currentPage + 1, append: true, appState: appState)
    }

    public func deleteThread(_ thread: MessageThread, appState: AppState) async {
        do {
            try await API.deleteMessageThread(ukey: thread.ukey)
            threads.removeAll { $0.id == thread.id }
            appState.showToast("已删除会话")
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func fetch(page: Int, append: Bool, appState: AppState) async {
        let expectedSession = appState.sessionVersion
        do {
            if segment == .chat {
                let items = try await API.messageThreads(page: page)
                guard expectedSession == appState.sessionVersion else { return }
                if append {
                    var seen = Set(threads.map(\.id))
                    let unique = items.filter { seen.insert($0.id).inserted }
                    threads.append(contentsOf: unique)
                    hasMore = !unique.isEmpty
                } else {
                    threads = items
                    hasMore = !items.isEmpty
                }
                currentPage = page
            } else {
                let items = try await API.notifications(type: segment.notificationEndpointType, page: page)
                guard expectedSession == appState.sessionVersion else { return }
                if append {
                    var seen = Set(notifications.map(\.id))
                    let unique = items.filter { seen.insert($0.id).inserted }
                    notifications.append(contentsOf: unique)
                    hasMore = !unique.isEmpty
                } else {
                    notifications = items
                    hasMore = !items.isEmpty
                }
                currentPage = page
            }
        } catch {
            guard expectedSession == appState.sessionVersion else { return }
            let retried = await appState.handleAPIError(error)
            if retried && !append {
                await fetch(page: page, append: false, appState: appState)
                return
            }
            if !append { errorMessage = error.localizedDescription }
        }
    }
}
