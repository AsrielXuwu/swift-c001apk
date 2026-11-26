import CoolapkKit
import SwiftUI

public struct MessagesView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MessagesViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("消息分类", selection: $viewModel.segment) {
                ForEach(MessagesSegment.allCases) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            content
        }
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(appState.sessionVersion)|\(viewModel.segment.rawValue)") {
            await viewModel.loadInitial(appState: appState, force: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !appState.accounts.isLoggedIn {
            ContentUnavailableView {
                Label("登录后查看消息", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("登录酷安账号即可接收评论回复、@提及、点赞通知和私信聊天。")
            } actions: {
                Button("立即登录") { appState.showLoginSheet = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if viewModel.isLoading && viewModel.threads.isEmpty && viewModel.notifications.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.segment == .chat {
            if viewModel.threads.isEmpty {
                ContentUnavailableView("暂无私信", systemImage: "envelope.open")
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
                                Task { await viewModel.loadMore(appState: appState) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.loadInitial(appState: appState, force: true)
                }
            }
        } else {
            if viewModel.notifications.isEmpty {
                ContentUnavailableView("暂无\(viewModel.segment.rawValue)", systemImage: "bell")
            } else {
                List {
                    ForEach(Array(viewModel.notifications.enumerated()), id: \.element.id) { index, item in
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
                            if index >= viewModel.notifications.count - 4 {
                                Task { await viewModel.loadMore(appState: appState) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.loadInitial(appState: appState, force: true)
                }
            }
        }
    }
}
