import CoolapkKit
import SwiftUI
import UIKit

public struct ReplyThreadSheet: View {
    public let rootReply: ReplyItem
    public let feedAuthorUID: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReplyItem] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var currentPage = 1
    @State private var threadComposeMode: ComposeMode?

    public init(rootReply: ReplyItem, feedAuthorUID: String) {
        self.rootReply = rootReply
        self.feedAuthorUID = feedAuthorUID
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    sectionHeader("原评论")
                    replyCard(rootReply, isRoot: true)
                        .padding(.horizontal, 12)

                    sectionHeader("全部回复")

                    if (!hasLoaded || isLoading) && items.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else if items.isEmpty {
                        ContentUnavailableView("暂无楼中楼回复", systemImage: "bubble.right")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            SwipeableReplyCard(
                                onReply: { openReplyComposer(for: item) },
                                onLike: { Task { await toggleReplyLike(item) } },
                                isLiked: item.isLiked,
                                onCopy: {
                                    UIPasteboard.general.string = FeedHTMLParser.plainText(item.message)
                                    appState.showToast("已复制评论")
                                }
                            ) {
                                replyCard(item, isRoot: false)
                            }
                            .padding(.horizontal, 12)
                            .onAppear {
                                if items.count >= 8 && index >= items.count - 2 {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .refreshable {
                await loadInitial()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .c001NativeTopBar()
            .navigationTitle("评论详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openReplyComposer(for: rootReply)
                    } label: {
                        Label("回复", systemImage: "square.and.pencil")
                    }
                }
            }
            .task {
                await loadInitial()
            }
            .onChange(of: appState.feedRefreshTrigger) { _, _ in
                Task { await loadInitial() }
            }
        }
        .overlay {
            ComposeFloatingOverlayHost(composeMode: $threadComposeMode)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private func openReplyComposer(for target: ReplyItem) {
        if appState.accounts.isLoggedIn {
            threadComposeMode = .replyToComment(targetID: target.id, replyToName: target.username)
        } else {
            appState.showLoginSheet = true
        }
    }

    private func replyCard(_ reply: ReplyItem, isRoot: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if !reply.uid.isEmpty {
                    dismiss()
                    appState.push(.user(uid: reply.uid, initialUsername: reply.username, initialAvatar: reply.avatar))
                }
            } label: {
                AvatarView(url: reply.avatar, size: isRoot ? 38 : 34)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(reply.username)
                        .font(.subheadline.weight(.semibold))
                    if reply.uid == feedAuthorUID || reply.isAuthor {
                        Text("楼主")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text(Formatting.relativeTime(reply.dateline, fallback: reply.datelineText))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let prefix = (!isRoot && !reply.replyToName.isEmpty) ? "回复 @\(reply.replyToName)：" : ""
                RichTextView(
                    html: prefix + reply.message,
                    fontSize: 15 * appState.settings.fontScale,
                    showEmoji: appState.settings.showEmoji
                ) { link in
                    dismiss()
                    appState.openRawLink(link)
                }

                if !reply.mediaItems.isEmpty {
                    MediaGridView(items: reply.mediaItems) { idx in
                        appState.openMedia(reply.mediaItems, at: idx)
                    }
                }

                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            Task { await toggleReplyLike(reply) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: reply.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                if reply.likeNum > 0 { Text("\(reply.likeNum)").monospacedDigit() }
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .foregroundStyle(reply.isLiked ? Color.pink : Color.secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            openReplyComposer(for: reply)
                        } label: {
                            Label("回复", systemImage: "bubble.right")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .c001CardStyle(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            if !isRoot {
                openReplyComposer(for: reply)
            }
        }
    }

    private func toggleReplyLike(_ target: ReplyItem) async {
        guard appState.accounts.isLoggedIn else {
            appState.showLoginSheet = true
            return
        }
        let nextLiked = !target.isLiked
        do {
            try await API.likeReply(id: target.id, liked: nextLiked)
            if let idx = items.firstIndex(where: { $0.id == target.id }) {
                items[idx].isLiked = nextLiked
                items[idx].likeNum = max(0, items[idx].likeNum + (nextLiked ? 1 : -1))
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadInitial() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        currentPage = 1
        do {
            items = try await API.subReplies(replyID: rootReply.id, page: 1)
            hasMore = !items.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await API.subReplies(replyID: rootReply.id, page: currentPage + 1)
            var seen = Set(items.map(\.id))
            let unique = next.filter { seen.insert($0.id).inserted }
            items.append(contentsOf: unique)
            if unique.isEmpty { hasMore = false } else { currentPage += 1 }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}
