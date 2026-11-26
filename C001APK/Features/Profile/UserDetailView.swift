import CoolapkKit
import SwiftUI

public struct UserDetailView: View {
    public let uid: String

    @Environment(AppState.self) private var appState
    @State private var profile: UserProfile?
    @State private var rows: [HomeFeedRow] = []
    @State private var likedRows: [HomeFeedRow] = []
    @State private var userCollections: [CollectionItem] = []
    @State private var followers: [UserBrief] = []
    @State private var following: [UserBrief] = []
    @State private var tab: UserTab = .feeds
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false

    private enum UserTab: String, CaseIterable, Identifiable {
        case feeds = "动态"
        case likes = "赞过"
        case collections = "收藏夹"
        case following = "关注"
        case fans = "粉丝"

        var id: String { rawValue }
    }

    public init(uid: String) { self.uid = uid }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                headerCard

                Picker("栏目", selection: $tab) {
                    ForEach(UserTab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onChange(of: tab) { _, _ in
                    Task { await reloadTab() }
                }

                Divider()

                tabBody
            }
        }
        .navigationTitle(profile?.username ?? "用户主页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let profile, uid != appState.accounts.activeUID {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if appState.accounts.isLoggedIn {
                        Button {
                            appState.push(.chat(
                                ukey: profile.id,
                                uid: profile.id,
                                username: profile.username,
                                avatar: profile.avatar
                            ))
                        } label: {
                            Image(systemName: "envelope")
                        }
                    }

                    Menu {
                        Button {
                            toggleLocalFollow(profile: profile)
                        } label: {
                            Label(
                                appState.localFollow.contains(uid: profile.id) ? "取消本机关注" : "加入本机/悄悄关注",
                                systemImage: "eye.slash"
                            )
                        }
                        Button(role: .destructive) {
                            appState.blacklist.toggleUser(profile.id)
                            appState.showToast(appState.blacklist.isUserBlocked(profile.id) ? "已加入黑名单" : "已移出黑名单")
                        } label: {
                            Label(
                                appState.blacklist.isUserBlocked(profile.id) ? "移出黑名单" : "屏蔽此用户",
                                systemImage: "hand.raised"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task(id: uid) {
            profile = try? await API.userProfile(uid: uid)
            await reloadTab()
        }
    }

    @ViewBuilder
    private var headerCard: some View {
        if let profile {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    AvatarView(url: profile.avatar, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(profile.username)
                                .font(.title3.weight(.bold))
                            Text("Lv.\(profile.level)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                        if !profile.verifyLabel.isEmpty {
                            Text(profile.verifyLabel)
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                        if !profile.location.isEmpty {
                            Text(profile.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    if uid != appState.accounts.activeUID {
                        followButton(profile: profile)
                    }
                }

                if !profile.bio.isEmpty {
                    Text(profile.bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 20) {
                    Text("\(Formatting.count(profile.feedNum)) 动态")
                    Text("\(Formatting.count(profile.followNum)) 关注")
                    Text("\(Formatting.count(profile.fansNum)) 粉丝")
                    if profile.likeNum > 0 {
                        Text("\(Formatting.count(profile.likeNum)) 获赞")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(16)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
    }

    private func followButton(profile: UserProfile) -> some View {
        let isLocalFollowed = appState.localFollow.contains(uid: profile.id)
        let labelText: String
        if appState.accounts.isLoggedIn {
            labelText = profile.isFollowed ? "已关注" : (isLocalFollowed ? "悄悄关注中" : "关注")
        } else {
            labelText = isLocalFollowed ? "已本地关注" : "本地关注"
        }

        return Text(labelText)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                (profile.isFollowed || isLocalFollowed) ? Color(.secondarySystemBackground) : Color.accentColor,
                in: Capsule()
            )
            .foregroundStyle((profile.isFollowed || isLocalFollowed) ? .primary : .white)
            .onTapGesture {
                Task { await handleFollowTap(profile: profile) }
            }
            .onLongPressGesture {
                if appState.accounts.isLoggedIn && appState.localFollow.secretFollowEnabled {
                    toggleLocalFollow(profile: profile)
                }
            }
    }

    @ViewBuilder
    private var tabBody: some View {
        if isLoading && rows.isEmpty && likedRows.isEmpty && userCollections.isEmpty && followers.isEmpty && following.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            switch tab {
            case .feeds:
                feedList(rows)
            case .likes:
                feedList(likedRows)
            case .collections:
                ForEach(userCollections) { item in
                    CollectionRowView(item: item)
                    Divider().padding(.leading, 16)
                }
            case .following:
                ForEach(following) { user in
                    UserRowView(user: user)
                    Divider().padding(.leading, 16)
                }
            case .fans:
                ForEach(followers) { user in
                    UserRowView(user: user)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private func feedList(_ items: [HomeFeedRow]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, row in
            HomeRowRenderer(row: row)
                .onAppear {
                    if idx >= items.count - 4 { Task { await loadMore() } }
                }
        }
    }

    private func reloadTab() async {
        isLoading = true
        defer { isLoading = false }
        page = 1
        hasMore = true
        do {
            switch tab {
            case .feeds:
                rows = try await API.userFeeds(uid: uid, page: 1)
                hasMore = !rows.isEmpty
            case .likes:
                likedRows = try await API.userLikeFeeds(uid: uid, page: 1)
                hasMore = !likedRows.isEmpty
            case .collections:
                userCollections = try await API.collectionList(uid: uid, page: 1)
                hasMore = !userCollections.isEmpty
            case .following:
                following = try await API.userList(uid: uid, followers: false, page: 1)
                hasMore = !following.isEmpty
            case .fans:
                followers = try await API.userList(uid: uid, followers: true, page: 1)
                hasMore = !followers.isEmpty
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let next = page + 1
        do {
            switch tab {
            case .feeds:
                let fetched = try await API.userFeeds(uid: uid, page: next)
                var seen = Set(rows.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                rows.append(contentsOf: unique)
                hasMore = !unique.isEmpty
            case .likes:
                let fetched = try await API.userLikeFeeds(uid: uid, page: next)
                var seen = Set(likedRows.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                likedRows.append(contentsOf: unique)
                hasMore = !unique.isEmpty
            case .collections, .following, .fans:
                hasMore = false
            }
            if hasMore { page = next }
        } catch {
            hasMore = false
        }
    }

    private func handleFollowTap(profile: UserProfile) async {
        guard appState.accounts.isLoggedIn else {
            toggleLocalFollow(profile: profile)
            return
        }
        let next = !profile.isFollowed
        do {
            try await API.followUser(uid: profile.id, follow: next)
            self.profile?.isFollowed = next
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func toggleLocalFollow(profile: UserProfile) {
        if appState.localFollow.contains(uid: profile.id) {
            appState.localFollow.unfollow(uid: profile.id)
            appState.showToast("已取消本机关注")
        } else {
            appState.localFollow.follow(uid: profile.id, username: profile.username, avatar: profile.avatar)
            appState.showToast(appState.accounts.isLoggedIn ? "已加入悄悄关注" : "已加入本机关注")
        }
    }
}
