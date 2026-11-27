import CoolapkKit
import SwiftUI

public struct MessagesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var viewModel = MessagesViewModel()
    @State private var scrolledSegment: MessagesSegment? = .chat
    @State private var transitionSeed = UUID().uuidString

    public init() {}

    public var body: some View {
        let totalUnread = viewModel.totalUnreadCount(appState: appState)
        let currentSegmentUnread = viewModel.unreadCount(for: viewModel.segment, appState: appState)

        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(MessagesSegment.allCases) { seg in
                    segmentContent(for: seg)
                        .containerRelativeFrame(.horizontal)
                        .frame(maxHeight: .infinity)
                        .id(seg)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledSegment)
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .bottom)
        .c001PageBackground()
        .safeAreaBar(edge: .top, spacing: 0) {
            floatingMessageSegmentStrip
        }
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appState.accounts.isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.markCurrentSegmentAllRead(appState: appState)
                            }
                        } label: {
                            Label("将「\(viewModel.segment.rawValue)」全部标为已读", systemImage: "checkmark.circle")
                        }
                        .disabled(currentSegmentUnread == 0 && (viewModel.segment == .chat ? viewModel.threads.isEmpty : (viewModel.notificationsBySegment[viewModel.segment]?.isEmpty ?? true)))

                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.markAllSegmentsRead(appState: appState)
                            }
                        } label: {
                            Label("全部消息标为已读", systemImage: "checkmark.circle.fill")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: totalUnread > 0 || appState.hasUnreadMessages ? "checkmark.circle" : "checkmark.circle.fill")
                            Text("已读")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(totalUnread > 0 || appState.hasUnreadMessages ? Color.primary : Color.secondary)
                    } primaryAction: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.markAllSegmentsRead(appState: appState)
                        }
                    }
                    .accessibilityLabel("全部标为已读")
                }
            }
        }
        .onChange(of: scrolledSegment) { _, newSeg in
            if let newSeg, newSeg != viewModel.segment {
                viewModel.segment = newSeg
            }
        }
        .onChange(of: viewModel.segment) { _, newSeg in
            if scrolledSegment != newSeg {
                withAnimation(.snappy(duration: 0.22)) {
                    scrolledSegment = newSeg
                }
            }
        }
        .task(id: "\(appState.sessionVersion)|\(viewModel.segment.rawValue)") {
            await viewModel.loadInitial(segment: viewModel.segment, appState: appState)
        }
    }

    private var floatingMessageSegmentStrip: some View {
        FloatingTabStrip(
            items: MessagesSegment.allCases,
            selection: viewModel.segment,
            titleProvider: { $0.rawValue },
            badgeProvider: { seg in
                viewModel.unreadCount(for: seg, appState: appState)
            },
            onSelect: { seg in
                viewModel.segment = seg
            }
        )
    }

    @ViewBuilder
    private func segmentContent(for seg: MessagesSegment) -> some View {
        let isLoadingSeg = viewModel.loadingSegments.contains(seg)
        let hasLoadedSeg = viewModel.loadedSegments.contains(seg)
        let notifications = viewModel.notificationsBySegment[seg] ?? []

        if !appState.accounts.isLoggedIn {
            ContentUnavailableView {
                Label("登录后查看消息", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("登录酷安账号即可接收评论回复、@提及、点赞通知和私信聊天。")
            } actions: {
                Button("立即登录") { appState.showLoginSheet = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if seg == .chat {
            if (!hasLoadedSeg || isLoadingSeg) && viewModel.threads.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.threads.isEmpty {
                ContentUnavailableView("暂无私信", systemImage: "envelope.open")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0)
                        LazyVStack(spacing: 10) {
                            ForEach(Array(viewModel.threads.enumerated()), id: \.element.id) { index, thread in
                                let tid = "msg-chat-\(transitionSeed)-\(thread.id)"
                                let avatarTID = "msg-chat-avatar-\(transitionSeed)-\(thread.id)"
                                let unreadCount = appState.effectiveThreadUnreadCount(thread)
                                let isUnread = unreadCount > 0

                                Button {
                                    appState.setThreadRead(thread, isRead: true)
                                    appState.push(.chat(
                                        ukey: thread.ukey,
                                        uid: thread.uid,
                                        username: thread.username,
                                        avatar: thread.avatar,
                                        transitionID: tid
                                    ))
                                } label: {
                                    HStack(spacing: 12) {
                                        Button {
                                            if !thread.uid.isEmpty {
                                                appState.push(.user(
                                                    uid: thread.uid,
                                                    initialUsername: thread.username,
                                                    initialAvatar: thread.avatar,
                                                    transitionID: avatarTID
                                                ))
                                            }
                                        } label: {
                                            AvatarView(url: thread.avatar, size: 48)
                                                .applyZoomSource(id: avatarTID, in: zoomNamespace, cornerRadius: 24)
                                        }
                                        .buttonStyle(.plain)

                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(spacing: 8) {
                                                Text(thread.username)
                                                    .font(.body.weight(isUnread ? .bold : .semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Spacer(minLength: 8)
                                                Text(Formatting.relativeTime(thread.dateline))
                                                    .font(.caption)
                                                    .foregroundStyle(isUnread ? Color.accentColor : Color.secondary)
                                            }
                                            HStack(spacing: 8) {
                                                EmojiBundleStore.richEmojiText(
                                                    thread.message,
                                                    emojiPointSize: 16,
                                                    showEmoji: appState.settings.showEmoji,
                                                    enableLinks: false
                                                )
                                                .font(.subheadline)
                                                .foregroundStyle(isUnread ? .primary : .secondary)
                                                .lineLimit(1)
                                                .multilineTextAlignment(.leading)

                                                Spacer(minLength: 8)

                                                if unreadCount > 0 {
                                                    Text("\(unreadCount)")
                                                        .font(.caption2.weight(.bold))
                                                        .monospacedDigit()
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2)
                                                        .background(Color.accentColor, in: Capsule())
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .c001CardStyle(cornerRadius: 22)
                                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 22)
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        appState.setThreadRead(thread, isRead: true)
                                        appState.push(.chat(
                                            ukey: thread.ukey,
                                            uid: thread.uid,
                                            username: thread.username,
                                            avatar: thread.avatar,
                                            transitionID: tid
                                        ))
                                    } label: {
                                        Label("进入私信", systemImage: "bubble.left.and.bubble.right")
                                    }

                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            appState.setThreadRead(thread, isRead: isUnread)
                                        }
                                    } label: {
                                        Label(
                                            isUnread ? "标为已读" : "标为未读",
                                            systemImage: isUnread ? "envelope.open" : "envelope.badge"
                                        )
                                    }

                                    if !thread.uid.isEmpty {
                                        Button {
                                            appState.push(.user(
                                                uid: thread.uid,
                                                initialUsername: thread.username,
                                                initialAvatar: thread.avatar,
                                                transitionID: avatarTID
                                            ))
                                        } label: {
                                            Label("查看用户空间", systemImage: "person.crop.circle")
                                        }
                                    }

                                    Divider()

                                    Button("删除会话", role: .destructive) {
                                        Task { await viewModel.deleteThread(thread, appState: appState) }
                                    }
                                }
                                .transition(.opacity)
                                .onAppear {
                                    if index >= viewModel.threads.count - 4 {
                                        Task { await viewModel.loadMore(segment: .chat, appState: appState) }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 42)
                    }
                }
                .refreshable {
                    await viewModel.loadInitial(segment: .chat, appState: appState, force: true)
                }
            }
        } else {
            if (!hasLoadedSeg || isLoadingSeg) && notifications.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorBySegment[seg], notifications.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await viewModel.loadInitial(segment: seg, appState: appState, force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notifications.isEmpty {
                ContentUnavailableView("暂无\(seg.rawValue)", systemImage: "bell")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0)
                        LazyVStack(spacing: 10) {
                            ForEach(Array(notifications.enumerated()), id: \.element.id) { index, item in
                                let tid = "msg-\(seg.rawValue)-\(transitionSeed)-\(item.id)"
                                let avatarTID = "msg-avatar-\(seg.rawValue)-\(transitionSeed)-\(item.id)"
                                let isRead = appState.isNotificationRead(item)

                                Button {
                                    openNotificationTarget(item, segment: seg, transitionID: tid, avatarTransitionID: avatarTID)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Button {
                                            appState.setNotificationRead(item, isRead: true, endpointType: seg.notificationEndpointType)
                                            if !item.uid.isEmpty {
                                                appState.push(.user(
                                                    uid: item.uid,
                                                    initialUsername: item.username,
                                                    initialAvatar: item.avatar,
                                                    transitionID: avatarTID
                                                ))
                                            } else {
                                                openNotificationTarget(item, segment: seg, transitionID: tid, avatarTransitionID: avatarTID)
                                            }
                                        } label: {
                                            AvatarView(url: item.avatar, size: 44)
                                                .applyZoomSource(id: avatarTID, in: zoomNamespace, cornerRadius: 22)
                                        }
                                        .buttonStyle(.plain)

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Text(item.username.isEmpty ? "系统通知" : item.username)
                                                    .font(.body.weight(isRead ? .semibold : .bold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                if !item.action.isEmpty {
                                                    Text(item.action)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                                Spacer(minLength: 8)
                                                if !isRead {
                                                    Circle()
                                                        .fill(Color.accentColor)
                                                        .frame(width: 8, height: 8)
                                                }
                                                Text(Formatting.relativeTime(item.dateline, fallback: item.datelineText))
                                                    .font(.caption)
                                                    .foregroundStyle(isRead ? Color.secondary : Color.accentColor)
                                            }
                                            if !item.message.isEmpty {
                                                EmojiBundleStore.richEmojiText(
                                                    item.message,
                                                    emojiPointSize: 17 * appState.settings.fontScale,
                                                    showEmoji: appState.settings.showEmoji,
                                                    enableLinks: false
                                                )
                                                .font(.system(size: 15 * appState.settings.fontScale))
                                                .foregroundStyle(isRead ? Color.primary.opacity(0.88) : Color.primary)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                            }
                                            if !item.extraTitle.isEmpty {
                                                HStack(spacing: 8) {
                                                    Text(item.extraTitle)
                                                        .font(.footnote)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.leading)
                                                    Spacer(minLength: 4)
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(.tertiary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .c001NestedSurface(cornerRadius: 14)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .c001CardStyle(cornerRadius: 22)
                                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 22)
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        openNotificationTarget(item, segment: seg, transitionID: tid, avatarTransitionID: avatarTID)
                                    } label: {
                                        Label("查看详情", systemImage: "arrow.up.right.square")
                                    }

                                    if !item.uid.isEmpty {
                                        Button {
                                            appState.setNotificationRead(item, isRead: true, endpointType: seg.notificationEndpointType)
                                            appState.push(.user(
                                                uid: item.uid,
                                                initialUsername: item.username,
                                                initialAvatar: item.avatar,
                                                transitionID: avatarTID
                                            ))
                                        } label: {
                                            Label("进入「\(item.username.isEmpty ? "用户" : item.username)」主页", systemImage: "person.crop.circle")
                                        }
                                    }

                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            appState.setNotificationRead(item, isRead: !isRead, endpointType: seg.notificationEndpointType)
                                        }
                                    } label: {
                                        Label(
                                            isRead ? "标为未读" : "标为已读",
                                            systemImage: isRead ? "circle.fill" : "checkmark.circle"
                                        )
                                    }
                                }
                                .transition(.opacity)
                                .onAppear {
                                    if index >= notifications.count - 4 {
                                        Task { await viewModel.loadMore(segment: seg, appState: appState) }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 42)
                    }
                }
                .refreshable {
                    await viewModel.loadInitial(segment: seg, appState: appState, force: true)
                }
            }
        }
    }

    private func openNotificationTarget(
        _ item: NotificationItem,
        segment: MessagesSegment,
        transitionID: String,
        avatarTransitionID: String
    ) {
        appState.setNotificationRead(item, isRead: true, endpointType: segment.notificationEndpointType)

        // 1. Follow notification -> go directly to the follower's user space
        if segment == .follow || item.isFollowNotification {
            if !item.uid.isEmpty {
                appState.push(.user(
                    uid: item.uid,
                    initialUsername: item.username,
                    initialAvatar: item.avatar,
                    transitionID: avatarTransitionID
                ))
                return
            }
        }

        // 2. Notification with resolved parent feed ID (comment, reply, @me, like) -> open FeedDetailView directly
        if !item.feedID.isEmpty {
            appState.push(.feed(
                id: item.feedID,
                initial: item.initialFeed,
                transitionID: transitionID
            ))
            return
        }

        // 3. Resolved targetURL (if it maps to user, feed, topic, product, etc.)
        if !item.targetURL.isEmpty, let resolved = FeedLink.resolve(item.targetURL) {
            switch resolved {
            case let .user(targetUID):
                let isSameActor = (targetUID == item.uid)
                appState.push(.user(
                    uid: targetUID,
                    initialUsername: isSameActor ? item.username : nil,
                    initialAvatar: isSameActor ? item.avatar : nil,
                    transitionID: isSameActor ? avatarTransitionID : transitionID
                ))
                return
            case let .feed(fid), let .question(fid), let .vote(fid):
                appState.push(.feed(
                    id: fid,
                    initial: item.initialFeed,
                    transitionID: transitionID
                ))
                return
            case .page:
                // Avoid pushing internal /notification/... or unsupported dataList links that fail with "无法访问该数据"
                if !item.uid.isEmpty {
                    appState.push(.user(
                        uid: item.uid,
                        initialUsername: item.username,
                        initialAvatar: item.avatar,
                        transitionID: avatarTransitionID
                    ))
                    return
                }
            default:
                appState.push(AppRoute.from(feedLink: resolved, transitionID: transitionID))
                return
            }
        }

        // 4. Fallback to actor's user profile
        if !item.uid.isEmpty {
            appState.push(.user(
                uid: item.uid,
                initialUsername: item.username,
                initialAvatar: item.avatar,
                transitionID: avatarTransitionID
            ))
        }
    }
}
