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
        .environment(\.openURL, OpenURLAction { url in
            appState.openRawLink(url.absoluteString)
            return .handled
        })
    }

    private var floatingMessageSegmentStrip: some View {
        FloatingTabStrip(
            items: MessagesSegment.allCases,
            selection: viewModel.segment,
            titleProvider: { $0.rawValue },
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
                    LazyVStack(spacing: 10) {
                        ForEach(Array(viewModel.threads.enumerated()), id: \.element.id) { index, thread in
                            let tid = "msg-chat-\(transitionSeed)-\(thread.id)"
                            Button {
                                appState.push(.chat(
                                    ukey: thread.ukey,
                                    uid: thread.uid,
                                    username: thread.username,
                                    avatar: thread.avatar,
                                    transitionID: tid
                                ))
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(url: thread.avatar, size: 48)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 8) {
                                            Text(thread.username)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Spacer(minLength: 8)
                                            Text(Formatting.relativeTime(thread.dateline))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 8) {
                                            EmojiBundleStore.richEmojiText(
                                                thread.message,
                                                emojiPointSize: 16,
                                                showEmoji: appState.settings.showEmoji
                                            )
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .multilineTextAlignment(.leading)

                                            Spacer(minLength: 8)

                                            if thread.unreadNum > 0 {
                                                Text("\(thread.unreadNum)")
                                                    .font(.caption2.weight(.bold))
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
                                .c001CardStyle(cornerRadius: 20)
                                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 20)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
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

                                Button("删除会话", role: .destructive) {
                                    Task { await viewModel.deleteThread(thread, appState: appState) }
                                }
                            }
                            .onAppear {
                                if index >= viewModel.threads.count - 4 {
                                    Task { await viewModel.loadMore(segment: .chat, appState: appState) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, 32)
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
                    LazyVStack(spacing: 10) {
                        ForEach(Array(notifications.enumerated()), id: \.element.id) { index, item in
                            let tid = "msg-\(seg.rawValue)-\(transitionSeed)-\(item.id)"
                            Button {
                                if !item.url.isEmpty {
                                    appState.openRawLink(item.url, transitionID: tid)
                                } else if !item.uid.isEmpty {
                                    appState.push(.user(
                                        uid: item.uid,
                                        initialUsername: item.username,
                                        initialAvatar: item.avatar,
                                        transitionID: tid
                                    ))
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    AvatarView(url: item.avatar, size: 42)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Text(item.username.isEmpty ? "系统通知" : item.username)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            if !item.action.isEmpty {
                                                Text(item.action)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 8)
                                            Text(Formatting.relativeTime(item.dateline, fallback: item.datelineText))
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        if !item.message.isEmpty {
                                            EmojiBundleStore.richEmojiText(
                                                item.message,
                                                emojiPointSize: 16,
                                                showEmoji: appState.settings.showEmoji
                                            )
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                        }
                                        if !item.extraTitle.isEmpty {
                                            Text(item.extraTitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .c001NestedSurface(cornerRadius: 10)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .c001CardStyle(cornerRadius: 20)
                                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 20)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if index >= notifications.count - 4 {
                                    Task { await viewModel.loadMore(segment: seg, appState: appState) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await viewModel.loadInitial(segment: seg, appState: appState, force: true)
                }
            }
        }
    }
}
