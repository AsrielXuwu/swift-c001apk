import CoolapkKit
import Foundation
import Observation
import SwiftUI

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
        case .reply: return "commentMeList"
        case .atMe: return "atMeList"
        case .likes: return "feedLikeList"
        case .follow: return "contactsFollowList"
        case .system: return "list"
        }
    }
}

@MainActor
@Observable
public final class MessagesViewModel {
    public var segment: MessagesSegment = .chat
    public private(set) var threads: [MessageThread] = []
    public private(set) var notificationsBySegment: [MessagesSegment: [NotificationItem]] = [:]
    public private(set) var loadingSegments: Set<MessagesSegment> = []
    public private(set) var loadedSegments: Set<MessagesSegment> = []
    public private(set) var loadingMoreSegments: Set<MessagesSegment> = []
    public private(set) var hasMoreBySegment: [MessagesSegment: Bool] = [:]
    public private(set) var errorBySegment: [MessagesSegment: String] = [:]

    private var pageBySegment: [MessagesSegment: Int] = [:]
    private var sessionMarker = -1

    public init() {}

    public func syncSessionIfNeeded(appState: AppState) {
        if sessionMarker != appState.sessionVersion {
            sessionMarker = appState.sessionVersion
            threads = []
            notificationsBySegment.removeAll()
            loadingSegments.removeAll()
            loadedSegments.removeAll()
            loadingMoreSegments.removeAll()
            hasMoreBySegment.removeAll()
            errorBySegment.removeAll()
            pageBySegment.removeAll()
        }
    }

    public func unreadCount(for targetSegment: MessagesSegment, appState: AppState) -> Int {
        switch targetSegment {
        case .chat:
            if loadedSegments.contains(.chat) {
                return threads.reduce(0) { $0 + appState.effectiveThreadUnreadCount($1) }
            }
            return appState.badge.message
        case .reply:
            if loadedSegments.contains(.reply), let items = notificationsBySegment[.reply] {
                return items.filter { !appState.isNotificationRead($0) }.count
            }
            return appState.badge.commentMe
        case .atMe:
            if loadedSegments.contains(.atMe), let items = notificationsBySegment[.atMe] {
                return items.filter { !appState.isNotificationRead($0) }.count
            }
            return appState.badge.atMe + appState.badge.atCommentMe
        case .likes:
            if loadedSegments.contains(.likes), let items = notificationsBySegment[.likes] {
                return items.filter { !appState.isNotificationRead($0) }.count
            }
            return appState.badge.feedLike
        case .follow:
            if loadedSegments.contains(.follow), let items = notificationsBySegment[.follow] {
                return items.filter { !appState.isNotificationRead($0) }.count
            }
            return appState.badge.contactsFollow
        case .system:
            if loadedSegments.contains(.system), let items = notificationsBySegment[.system] {
                return items.filter { !appState.isNotificationRead($0) }.count
            }
            return appState.badge.notification
        }
    }

    public func totalUnreadCount(appState: AppState) -> Int {
        MessagesSegment.allCases.reduce(0) { $0 + unreadCount(for: $1, appState: appState) }
    }

    public func markCurrentSegmentAllRead(appState: AppState) {
        let items = notificationsBySegment[segment] ?? []
        appState.markSegmentRead(
            endpointType: segment.notificationEndpointType,
            threads: threads,
            notifications: items
        )
        appState.showToast("已将「\(segment.rawValue)」标为已读")
    }

    public func markAllSegmentsRead(appState: AppState) {
        var mapped: [String: [NotificationItem]] = [:]
        for (seg, list) in notificationsBySegment {
            mapped[seg.rawValue] = list
        }
        appState.markAllMessagesAndNotificationsRead(
            threads: threads,
            notificationsBySegment: mapped
        )
        appState.showToast("已将全部消息标为已读")
    }

    public func loadInitial(segment targetSegment: MessagesSegment, appState: AppState, force: Bool = false) async {
        syncSessionIfNeeded(appState: appState)
        guard appState.accounts.isLoggedIn else {
            threads = []
            notificationsBySegment.removeAll()
            return
        }
        if !force {
            if targetSegment == .chat, !threads.isEmpty { return }
            if targetSegment != .chat, let existing = notificationsBySegment[targetSegment], !existing.isEmpty { return }
        }
        pageBySegment[targetSegment] = 1
        hasMoreBySegment[targetSegment] = true
        errorBySegment[targetSegment] = nil
        loadingSegments.insert(targetSegment)
        defer {
            loadingSegments.remove(targetSegment)
            loadedSegments.insert(targetSegment)
        }
        await fetch(segment: targetSegment, page: 1, append: false, appState: appState)
        await appState.refreshBadgeOnly()
    }

    public func loadMore(segment targetSegment: MessagesSegment, appState: AppState) async {
        guard !loadingSegments.contains(targetSegment),
              !loadingMoreSegments.contains(targetSegment),
              hasMoreBySegment[targetSegment] != false,
              appState.accounts.isLoggedIn else { return }
        loadingMoreSegments.insert(targetSegment)
        defer { loadingMoreSegments.remove(targetSegment) }
        let nextPage = (pageBySegment[targetSegment] ?? 1) + 1
        await fetch(segment: targetSegment, page: nextPage, append: true, appState: appState)
    }

    public func deleteThread(_ thread: MessageThread, appState: AppState) async {
        do {
            try await API.deleteMessageThread(ukey: thread.ukey)
            withAnimation(.snappy(duration: 0.22)) {
                threads.removeAll { $0.id == thread.id }
            }
            appState.showToast("已删除会话")
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func fetch(segment targetSegment: MessagesSegment, page: Int, append: Bool, appState: AppState) async {
        let expectedSession = appState.sessionVersion
        do {
            if targetSegment == .chat {
                let items = try await API.messageThreads(page: page)
                guard expectedSession == appState.sessionVersion else { return }
                if append {
                    var seen = Set(threads.map(\.id))
                    let unique = items.filter { seen.insert($0.id).inserted }
                    withAnimation(.smooth(duration: 0.24)) {
                        threads.append(contentsOf: unique)
                    }
                    hasMoreBySegment[targetSegment] = !unique.isEmpty
                } else {
                    withAnimation(.smooth(duration: 0.24)) {
                        threads = items
                    }
                    hasMoreBySegment[targetSegment] = !items.isEmpty
                }
                pageBySegment[targetSegment] = page
            } else {
                let items = try await API.notifications(type: targetSegment.notificationEndpointType, page: page)
                guard expectedSession == appState.sessionVersion else { return }
                for item in items {
                    if let initialFeed = item.initialFeed {
                        appState.cacheFeedDetail(initialFeed, verified: false)
                    }
                }
                if append {
                    let current = notificationsBySegment[targetSegment] ?? []
                    var seen = Set(current.map(\.id))
                    let unique = items.filter { seen.insert($0.id).inserted }
                    withAnimation(.smooth(duration: 0.24)) {
                        notificationsBySegment[targetSegment] = current + unique
                    }
                    hasMoreBySegment[targetSegment] = !unique.isEmpty
                } else {
                    withAnimation(.smooth(duration: 0.24)) {
                        notificationsBySegment[targetSegment] = items
                    }
                    hasMoreBySegment[targetSegment] = !items.isEmpty
                }
                pageBySegment[targetSegment] = page
            }
        } catch {
            guard expectedSession == appState.sessionVersion else { return }
            let retried = await appState.handleAPIError(error)
            if retried && !append {
                await fetch(segment: targetSegment, page: page, append: false, appState: appState)
                return
            }
            if !append { errorBySegment[targetSegment] = error.localizedDescription }
        }
    }
}
