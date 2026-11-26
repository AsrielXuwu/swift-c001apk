import CoolapkKit
import SwiftUI
import UIKit

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
                                badgeIsCloud: nil,
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
                .scrollEdgeEffectStyle(.soft, for: .top)
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
    @State private var selectedFolderID: String? = nil

    public init() {}

    private var visibleFavorites: [LocalFavoriteEntry] {
        appState.historyAndFav.favorites(inFolder: selectedFolderID)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                sectionHeader("收藏夹列表")

                if !appState.settings.enableCloudFavoritesLoad && appState.accounts.isLoggedIn {
                    Text("已关闭云端收藏夹加载，仅显示本机收藏数据（可在设置开启）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                // Local folders with "本地" corner badge
                ForEach(appState.historyAndFav.folders) { folder in
                    let isSelected = selectedFolderID == folder.id
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedFolderID = isSelected ? nil : folder.id
                        }
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill((folder.isCloudLinked ? Color.blue : Color.accentColor).opacity(0.14))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: folder.isCloudLinked ? "icloud" : "bookmark.fill")
                                        .foregroundStyle(folder.isCloudLinked ? Color.blue : Color.accentColor)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(folder.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    SourceOriginBadge(isCloud: false)
                                }
                                Text("\(appState.historyAndFav.count(inFolder: folder.id)) 条已缓存动态" + (isSelected ? " · 当前筛选中" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 20)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if folder.id != HistoryAndFavStore.defaultFolderID {
                            Button("删除收藏夹", role: .destructive) {
                                if selectedFolderID == folder.id { selectedFolderID = nil }
                                appState.historyAndFav.deleteFolder(id: folder.id)
                            }
                        }
                    }
                }

                // Cloud collections with "云端" corner badge
                if appState.settings.enableCloudFavoritesLoad && !remoteCollections.isEmpty {
                    ForEach(remoteCollections) { col in
                        CollectionRowView(item: col)
                            .overlay(alignment: .topTrailing) {
                                SourceOriginBadge(isCloud: true)
                                    .padding(.top, 10)
                                    .padding(.trailing, 22)
                            }
                    }
                }

                HStack {
                    sectionHeader(selectedFolderID == nil ? "全部收藏内容" : "当前收藏夹内容")
                    Spacer()
                    if selectedFolderID != nil {
                        Button("查看全部") {
                            withAnimation(.snappy) { selectedFolderID = nil }
                        }
                        .font(.caption.weight(.medium))
                        .padding(.trailing, 16)
                    }
                }

                if visibleFavorites.isEmpty {
                    Text("暂无收藏动态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .c001CardStyle(cornerRadius: 20)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(visibleFavorites) { entry in
                        StoredFeedCardRow(
                            feedID: entry.id,
                            snapshot: entry.feed,
                            fallbackTitle: entry.title,
                            fallbackPreview: entry.preview,
                            fallbackUsername: entry.username,
                            fallbackAvatar: entry.avatar,
                            fallbackDate: entry.savedAt,
                            badgeIsCloud: entry.resolvedIsCloudSynced,
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
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if let data = appState.historyAndFav.exportBackupJSON(),
                           let str = String(data: data, encoding: .utf8) {
                            UIPasteboard.general.string = str
                            appState.showToast("已复制收藏夹备份 JSON")
                        }
                    } label: {
                        Label("导出备份 JSON", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        if let text = UIPasteboard.general.string,
                           let data = text.data(using: .utf8) {
                            let count = appState.historyAndFav.importBackupJSON(data)
                            appState.showToast(count > 0 ? "已导入 \(count) 条收藏" : "剪贴板中未检测到新的收藏数据")
                        } else {
                            appState.showToast("剪贴板为空")
                        }
                    } label: {
                        Label("从剪贴板导入 JSON", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            if appState.settings.enableCloudFavoritesLoad,
               appState.accounts.isLoggedIn,
               let uid = appState.accounts.activeUID {
                remoteCollections = (try? await API.collectionList(uid: uid, page: 1)) ?? []
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}

public struct LocalFollowListView: View {
    @Environment(AppState.self) private var appState
    @State private var cloudUsers: [UserBrief] = []
    @State private var isLoadingCloud = false

    public init() {}

    public var body: some View {
        let localEmpty = appState.localFollow.users.isEmpty
        let cloudEmpty = !appState.settings.enableCloudFollowLoad || cloudUsers.isEmpty

        Group {
            if localEmpty && cloudEmpty && !isLoadingCloud {
                ContentUnavailableView {
                    Label("暂无关注用户", systemImage: "person.badge.shield.checkmark")
                } description: {
                    Text(appState.accounts.isLoggedIn
                         ? "长按用户主页的关注按钮即可加入本机悄悄关注；也可在设置开启云端关注读取。"
                         : "游客模式下点击用户主页的本地关注按钮即可加入。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !appState.settings.enableCloudFollowLoad && appState.accounts.isLoggedIn {
                            Text("已关闭云端关注列表加载，仅显示本机关注（可在设置开启）。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        }

                        if !appState.localFollow.users.isEmpty {
                            Text(appState.accounts.isLoggedIn ? "悄悄关注" : "本机关注")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

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
                                .overlay(alignment: .topTrailing) {
                                    SourceOriginBadge(isCloud: false)
                                        .padding(.top, 10)
                                        .padding(.trailing, 34)
                                }
                                .contextMenu {
                                    Button("取消本机关注", role: .destructive) {
                                        appState.localFollow.unfollow(uid: user.uid)
                                    }
                                }
                            }
                        }

                        if appState.settings.enableCloudFollowLoad && appState.accounts.isLoggedIn {
                            Text("云端关注")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)

                            if isLoadingCloud && cloudUsers.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            } else if cloudUsers.isEmpty {
                                Text("暂无云端关注用户")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ForEach(cloudUsers) { user in
                                    UserRowView(user: user)
                                        .overlay(alignment: .topTrailing) {
                                            SourceOriginBadge(isCloud: true)
                                                .padding(.top, 10)
                                                .padding(.trailing, 34)
                                        }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, 32)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(appState.accounts.isLoggedIn ? "管理悄悄关注" : "管理本机关注")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard appState.settings.enableCloudFollowLoad,
                  appState.accounts.isLoggedIn,
                  let uid = appState.accounts.activeUID,
                  cloudUsers.isEmpty else { return }
            isLoadingCloud = true
            defer { isLoadingCloud = false }
            cloudUsers = (try? await API.userList(uid: uid, followers: false, page: 1)) ?? []
        }
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
    let badgeIsCloud: Bool?
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
        .overlay(alignment: .topTrailing) {
            if let badgeIsCloud {
                SourceOriginBadge(isCloud: badgeIsCloud)
                    .padding(.top, 12)
                    .padding(.trailing, 54)
                    .allowsHitTesting(false)
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
