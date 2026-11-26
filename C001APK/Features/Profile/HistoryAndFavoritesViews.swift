import CoolapkKit
import SwiftUI

public struct HistoryListView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        Group {
            if appState.historyAndFav.history.isEmpty {
                ContentUnavailableView("暂无浏览历史", systemImage: "clock")
            } else {
                List {
                    ForEach(appState.historyAndFav.history) { item in
                        Button {
                            appState.push(.feed(id: item.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title.isEmpty ? item.preview : item.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("\(item.username) · \(Formatting.relativeTime(item.visitedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                appState.historyAndFav.removeHistory(id: item.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
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
        List {
            if !remoteCollections.isEmpty {
                Section("账号收藏夹") {
                    ForEach(remoteCollections) { col in
                        Button {
                            appState.push(.collection(id: col.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(col.title).font(.body.weight(.medium))
                                Text("\(col.itemNum) 项内容").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("本机收藏") {
                if appState.historyAndFav.favorites.isEmpty {
                    Text("暂无本机收藏动态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.historyAndFav.favorites) { item in
                        Button {
                            appState.push(.feed(id: item.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title.isEmpty ? item.preview : item.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Text("\(item.username) · \(Formatting.relativeTime(item.savedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("移除", role: .destructive) {
                                appState.historyAndFav.removeFavorite(id: item.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if appState.accounts.isLoggedIn, let uid = appState.accounts.activeUID {
                remoteCollections = (try? await API.collectionList(uid: uid, page: 1)) ?? []
            }
        }
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
            } else {
                List {
                    ForEach(appState.localFollow.users) { user in
                        Button {
                            appState.push(.user(uid: user.uid))
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: user.avatar, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.username).font(.body.weight(.medium))
                                    Text("UID: \(user.uid)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("移除", role: .destructive) {
                                appState.localFollow.unfollow(uid: user.uid)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(appState.accounts.isLoggedIn ? "管理悄悄关注" : "管理本机关注")
        .navigationBarTitleDisplayMode(.inline)
    }
}
