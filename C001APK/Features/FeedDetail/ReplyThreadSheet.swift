import CoolapkKit
import SwiftUI

public struct ReplyThreadSheet: View {
    public let rootReply: ReplyItem
    public let feedAuthorUID: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReplyItem] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var currentPage = 1

    public init(rootReply: ReplyItem, feedAuthorUID: String) {
        self.rootReply = rootReply
        self.feedAuthorUID = feedAuthorUID
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    replyRow(rootReply, isRoot: true)
                    Divider()

                    if isLoading && items.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            replyRow(item, isRoot: false)
                                .onAppear {
                                    if index >= items.count - 4 {
                                        Task { await loadMore() }
                                    }
                                }
                            Divider().padding(.leading, 56)
                        }
                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                }
            }
            .navigationTitle("评论详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if appState.accounts.isLoggedIn {
                            appState.composeMode = .replyToComment(targetID: rootReply.id, replyToName: rootReply.username)
                        } else {
                            appState.showLoginSheet = true
                        }
                    } label: {
                        Label("回复", systemImage: "square.and.pencil")
                    }
                }
            }
            .task {
                await loadInitial()
            }
        }
    }

    private func replyRow(_ reply: ReplyItem, isRoot: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                if !reply.uid.isEmpty {
                    dismiss()
                    appState.push(.user(uid: reply.uid))
                }
            } label: {
                AvatarView(url: reply.avatar, size: isRoot ? 38 : 32)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(reply.username)
                        .font(.subheadline.weight(.semibold))
                    if reply.uid == feedAuthorUID || reply.isAuthor {
                        Text("楼主")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isRoot ? Color(.secondarySystemBackground).opacity(0.5) : Color.clear)
    }

    private func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
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
