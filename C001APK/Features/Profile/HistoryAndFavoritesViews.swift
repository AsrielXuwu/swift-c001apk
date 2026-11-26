import CoolapkKit
import SwiftUI

public struct HistoryListView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        Group {
            if appState.historyAndFav.history.isEmpty {
                ContentUnavailableView("暂无浏览历史", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.historyAndFav.history) { entry in
                            StoredFeedCardRow(
                                feedID: entry.id,
                                snapshot: entry.feed,
                                fallbackTitle: entry.title,
                                fallbackPreview: entry.preview,
                                fallbackUsername: entry.username,
                                fallbackAvatar: entry.avatar,
                                fallbackDate: entry.visitedAt,
                                deleteTitle: "删除此条历史",
                                onDelete: {
                                    appState.historyAndFav.removeHistory(id: entry.id)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, 32)
                }
                .scrollEdgeEffectHidden(true, for: .top)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("浏览历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !appState.historyAndFav.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        appState.historyAndFav.clearHistory()
                    }
                }
            }
        }
    }
}

public struct FavoritesListView: View {
    @Environment(AppState.self) private var appState
    @State private var remoteCollections: [CollectionItem] = []

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !remoteCollections.isEmpty {
                    sectionLabel("账号收藏夹")
                    ForEach(remoteCollections) { col in
                        CollectionRowView(item: col)
                    }
                }

                sectionLabel("本机收藏")
                if appState.historyAndFav.favorites.isEmpty {
                    Text("暂无本机收藏动态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .c001CardStyle(cornerRadius: 20)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(appState.historyAndFav.favorites) { entry in
                        StoredFeedCardRow(
                            feedID: entry.id,
                            snapshot: entry.feed,
                            fallbackTitle: entry.title,
                            fallbackPreview: entry.preview,
                            fallbackUsername: entry.username,
                            fallbackAvatar: entry.avatar,
                            fallbackDate: entry.savedAt,
                            deleteTitle: "移除收藏",
                            onDelete: {
                                appState.historyAndFav.removeFavorite(id: entry.id)
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if appState.accounts.isLoggedIn, let uid = appState.accounts.activeUID {
                remoteCollections = (try? await API.collectionList(uid: uid, page: 1)) ?? []
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}

public struct LocalFollowListView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        Group {
            if appState.localFollow.users.isEmpty {
                ContentUnavailableView {
                    Label("暂无本机关注", systemImage: "person.badge.shield.checkmark")
                } description: {
                    Text(appState.accounts.isLoggedIn
                         ? "开启悄悄关注后，长按用户主页的关注按钮即可加入本机名单，不会向服务器发起关注。"
                         : "游客模式下点击用户主页的本地关注按钮即可加入。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.localFollow.users) { user in
                            UserRowView(
                                user: UserBrief(
                                    id: user.uid,
                                    username: user.username,
                                    avatar: user.avatar,
                                    isFollowed: true,
                                    bio: "UID: \(user.uid)"
                                )
                            )
                            .contextMenu {
                                Button("取消本机关注", role: .destructive) {
                                    appState.localFollow.unfollow(uid: user.uid)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, 32)
                }
                .scrollEdgeEffectHidden(true, for: .top)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(appState.accounts.isLoggedIn ? "管理悄悄关注" : "管理本机关注")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StoredFeedCardRow: View {
    let feedID: String
    let snapshot: FeedItem?
    let fallbackTitle: String
    let fallbackPreview: String
    let fallbackUsername: String
    let fallbackAvatar: String
    let fallbackDate: Date
    let deleteTitle: String
    let onDelete: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var hydrated: FeedItem?
    @State private var didAttemptHydration = false
    @State private var transitionSeed = UUID().uuidString

    var body: some View {
        Group {
            if let feed = snapshot ?? hydrated {
                FeedRowView(feed: feed)
            } else {
                legacyFallbackCard
            }
        }
        .contextMenu {
            Button(deleteTitle, role: .destructive) {
                onDelete()
            }
        }
        .task(id: feedID) {
            guard snapshot == nil, hydrated == nil, !didAttemptHydration, !feedID.isEmpty else { return }
            didAttemptHydration = true
            if let fetched = try? await API.feedDetail(id: feedID) {
                hydrated = fetched
                appState.historyAndFav.backfillSnapshot(fetched)
            }
        }
    }

    private var legacyFallbackCard: some View {
        let tid = "stored-\(feedID)-\(transitionSeed)"
        return Button {
            appState.push(.feed(id: feedID, transitionID: tid))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AvatarView(url: fallbackAvatar, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fallbackUsername.isEmpty ? "酷友" : fallbackUsername)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(Formatting.relativeTime(fallbackDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if !fallbackTitle.isEmpty {
                    Text(fallbackTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if !fallbackPreview.isEmpty {
                    Text(fallbackPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: tid, in: zoomNamespace)
        }
        .buttonStyle(.plain)
    }
}
