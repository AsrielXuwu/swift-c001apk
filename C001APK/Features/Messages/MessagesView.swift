import CoolapkKit
import SwiftUI

public struct MessagesView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MessagesViewModel()
    @State private var scrolledSegment: MessagesSegment? = .chat

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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
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
    }

    private var floatingMessageSegmentStrip: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(MessagesSegment.allCases) { seg in
                    let isSelected = viewModel.segment == seg
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.segment = seg
                        }
                    } label: {
                        Text(seg.rawValue)
                            .font(.caption.weight(isSelected ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func segmentContent(for seg: MessagesSegment) -> some View {
        let isLoadingSeg = viewModel.loadingSegments.contains(seg)
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
            if isLoadingSeg && viewModel.threads.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.threads.isEmpty {
                ContentUnavailableView("暂无私信", systemImage: "envelope.open")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(viewModel.threads.enumerated()), id: \.element.id) { index, thread in
                        Button {
                            appState.push(.chat(
                                ukey: thread.ukey,
                                uid: thread.uid,
                                username: thread.username,
                                avatar: thread.avatar
                            ))
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: thread.avatar, size: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(thread.username)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(Formatting.relativeTime(thread.dateline))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Text(FeedHTMLParser.plainText(thread.message))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        if thread.unreadNum > 0 {
                                            Text("\(thread.unreadNum)")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor, in: Capsule())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
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
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await viewModel.loadInitial(segment: .chat, appState: appState, force: true)
                }
            }
        } else {
            if isLoadingSeg && notifications.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notifications.isEmpty {
                ContentUnavailableView("暂无\(seg.rawValue)", systemImage: "bell")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(notifications.enumerated()), id: \.element.id) { index, item in
                        Button {
                            if !item.url.isEmpty {
                                appState.openRawLink(item.url)
                            } else if !item.uid.isEmpty {
                                appState.push(.user(uid: item.uid))
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                AvatarView(url: item.avatar, size: 40)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(item.username.isEmpty ? "系统通知" : item.username)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(item.action)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(Formatting.relativeTime(item.dateline, fallback: item.datelineText))
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    if !item.message.isEmpty {
                                        Text(FeedHTMLParser.plainText(item.message))
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                    }
                                    if !item.extraTitle.isEmpty {
                                        Text(item.extraTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if index >= notifications.count - 4 {
                                Task { await viewModel.loadMore(segment: seg, appState: appState) }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await viewModel.loadInitial(segment: seg, appState: appState, force: true)
                }
            }
        }
    }
}
