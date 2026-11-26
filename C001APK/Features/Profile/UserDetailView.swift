import CoolapkKit
import SwiftUI

public struct UserDetailView: View {
    public let uid: String
    public let initialUsername: String?
    public let initialAvatar: String?

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var profile: UserProfile?
    @State private var rows: [HomeFeedRow] = []
    @State private var likedRows: [HomeFeedRow] = []
    @State private var userCollections: [CollectionItem] = []
    @State private var followers: [UserBrief] = []
    @State private var following: [UserBrief] = []
    @State private var tab: UserTab = .feeds
    @State private var scrolledTab: UserTab? = .feeds
    @State private var loadedTabs: Set<UserTab> = []
    @State private var pageByTab: [UserTab: Int] = [:]
    @State private var hasMoreByTab: [UserTab: Bool] = [:]
    @State private var loadingTabs: Set<UserTab> = []
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var tabTasks: [UserTab: Task<Void, Never>] = [:]

    private enum UserTab: String, CaseIterable, Identifiable {
        case feeds = "动态"
        case likes = "赞过"
        case collections = "收藏夹"
        case following = "关注"
        case fans = "粉丝"

        var id: String { rawValue }
    }

    public init(uid: String, initialUsername: String? = nil, initialAvatar: String? = nil) {
        self.uid = uid
        self.initialUsername = initialUsername
        self.initialAvatar = initialAvatar
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(UserTab.allCases) { item in
                        tabScrollPage(for: item)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledTab)
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaBar(edge: .top, spacing: 0) {
                FloatingTabStrip(
                    items: UserTab.allCases,
                    selection: tab,
                    titleProvider: { $0.rawValue },
                    onSelect: { selected in
                        tab = selected
                    },
                    onReselect: { current in
                        withAnimation(.snappy) {
                            proxy.scrollTo("user-top-\(current.rawValue)", anchor: .top)
                        }
                    }
                )
            }
            .navigationTitle(profile?.username ?? initialUsername ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if compactNavProgress > 0.08, (profile != nil || initialAvatar != nil) {
                    let loginPrimary = profile?.loginTime.map { "活跃 · \(Formatting.relativeTime($0))" }
                        ?? (profile?.location.isEmpty == false ? profile!.location : "UID \(uid)")
                    let deviceSecondary = profile?.deviceTitle.isEmpty == false
                        ? profile!.deviceTitle
                        : (profile.map { "\(Formatting.count($0.fansNum)) 粉丝" } ?? "酷友主页")
                    CollapsedNavEntityToolbar(
                        avatarURL: profile?.avatar ?? initialAvatar ?? "",
                        primaryLine: loginPrimary,
                        secondaryLine: deviceSecondary,
                        isFollowed: profile.map(isFollowingUser) ?? appState.localFollow.contains(uid: uid),
                        showFollowButton: profile != nil && uid != appState.accounts.activeUID,
                        isDisabled: isTogglingFollow,
                        onTapAvatar: {
                            withAnimation(.snappy) {
                                proxy.scrollTo("user-top-\(tab.rawValue)", anchor: .top)
                            }
                        },
                        onTapFollow: {
                            if let profile {
                                Task { await handleFollowTap(profile: profile) }
                            }
                        }
                    )
                }

                if uid != appState.accounts.activeUID {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if appState.accounts.isLoggedIn {
                            Button {
                                appState.push(.chat(
                                    ukey: profile?.id ?? uid,
                                    uid: profile?.id ?? uid,
                                    username: profile?.username ?? initialUsername ?? "",
                                    avatar: profile?.avatar ?? initialAvatar ?? ""
                                ))
                            } label: {
                                Image(systemName: "envelope")
                            }
                        }

                        Menu {
                            Button {
                                if let profile {
                                    toggleLocalFollow(profile: profile)
                                } else {
                                    if appState.localFollow.contains(uid: uid) {
                                        appState.localFollow.unfollow(uid: uid)
                                        appState.showToast("已取消本机关注")
                                    } else {
                                        appState.localFollow.follow(
                                            uid: uid,
                                            username: initialUsername ?? uid,
                                            avatar: initialAvatar ?? ""
                                        )
                                        appState.showToast(appState.accounts.isLoggedIn ? "已加入悄悄关注" : "已加入本机关注")
                                    }
                                }
                            } label: {
                                Label(
                                    appState.localFollow.contains(uid: uid) ? "取消本机关注" : "加入本机/悄悄关注",
                                    systemImage: "eye.slash"
                                )
                            }
                            Button(role: .destructive) {
                                appState.blacklist.toggleUser(uid)
                                appState.showToast(appState.blacklist.isUserBlocked(uid) ? "已加入黑名单" : "已移出黑名单")
                            } label: {
                                Label(
                                    appState.blacklist.isUserBlocked(uid) ? "移出黑名单" : "屏蔽此用户",
                                    systemImage: "hand.raised"
                                )
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .onChange(of: scrolledTab) { _, newTab in
                if let newTab, newTab != tab {
                    tab = newTab
                }
            }
            .onChange(of: tab) { _, nextTab in
                if scrolledTab != nextTab {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrolledTab = nextTab
                    }
                }
                startLoadTab(nextTab, force: false)
            }
            .task(id: uid) {
                profile = try? await API.userProfile(uid: uid)
                await reloadTab(tab, force: true)
            }
        }
    }

    private func startLoadTab(_ targetTab: UserTab, force: Bool) {
        tabTasks[targetTab]?.cancel()
        tabTasks[targetTab] = Task {
            await reloadTab(targetTab, force: force)
        }
    }

    private func tabScrollPage(for item: UserTab) -> some View {
        ScrollView {
            Color.clear.frame(height: 0).id("user-top-\(item.rawValue)")
            LazyVStack(alignment: .leading, spacing: 12) {
                headerCard
                    .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                    .scaleEffect(1.0 - compactNavProgress * 0.03, anchor: .top)

                tabBody(for: item)
            }
            .padding(.top, 10)
            .padding(.bottom, 88)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, offset in
            guard item == tab else { return }
            let progress = min(1, max(0, (offset - 44) / 76))
            if abs(progress - compactNavProgress) > 0.02 {
                withAnimation(.easeOut(duration: 0.16)) {
                    compactNavProgress = progress
                }
            }
        }
        .refreshable {
            profile = try? await API.userProfile(uid: uid)
            await reloadTab(item, force: true)
        }
    }

    private func isFollowingUser(_ profile: UserProfile) -> Bool {
        let isLocal = appState.localFollow.contains(uid: profile.id)
        let isCloud = appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad && profile.isFollowed
        return isLocal || isCloud
    }

    @ViewBuilder
    private var headerCard: some View {
        if let profile {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Button {
                        if !profile.avatar.isEmpty {
                            appState.openMedia(
                                [FeedMedia(sourceUrl: profile.avatar)],
                                at: 0,
                                sourcePrefix: "user-avatar-\(transitionSeed)"
                            )
                        }
                    } label: {
                        AvatarView(url: profile.avatar, size: 64)
                            .applyZoomSource(id: "user-avatar-\(transitionSeed)-0", in: zoomNamespace)
                    }
                    .buttonStyle(.plain)

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
            .c001CardStyle(cornerRadius: 22)
            .padding(.horizontal, 12)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    AvatarView(url: initialAvatar ?? "", size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(initialUsername ?? "加载中…")
                            .font(.title3.weight(.bold))
                        Text("UID: \(uid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(16)
            .c001CardStyle(cornerRadius: 22)
            .padding(.horizontal, 12)
        }
    }

    private func followButton(profile: UserProfile) -> some View {
        let isLocalFollowed = appState.localFollow.contains(uid: profile.id)
        let isCloudFollowed = appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad && profile.isFollowed
        let labelText: String
        if isCloudFollowed && isLocalFollowed {
            labelText = "已关注"
        } else if isCloudFollowed {
            labelText = "已关注（云端）"
        } else if isLocalFollowed {
            labelText = "已关注（本机）"
        } else {
            labelText = "关注"
        }

        return Button {
            Task { await handleFollowTap(profile: profile) }
        } label: {
            HStack(spacing: 5) {
                if isTogglingFollow {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(labelText)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                (isCloudFollowed || isLocalFollowed) ? Color.clear : Color.accentColor.opacity(0.20),
                in: Capsule()
            )
            .glassEffect(.regular.interactive(), in: .capsule)
            .foregroundStyle((isCloudFollowed || isLocalFollowed) ? Color.primary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isTogglingFollow)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                if appState.accounts.isLoggedIn && appState.localFollow.secretFollowEnabled {
                    toggleLocalFollow(profile: profile)
                }
            }
        )
    }

    private func isTabEmpty(_ item: UserTab) -> Bool {
        switch item {
        case .feeds: return rows.isEmpty
        case .likes: return likedRows.isEmpty
        case .collections: return userCollections.isEmpty
        case .following: return following.isEmpty
        case .fans: return followers.isEmpty
        }
    }

    @ViewBuilder
    private func tabBody(for item: UserTab) -> some View {
        let isEmpty = isTabEmpty(item)
        let hasLoaded = loadedTabs.contains(item)
        let isLoadingTab = loadingTabs.contains(item)

        if (!hasLoaded || isLoadingTab) && isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.vertical, 40)
        } else if isEmpty {
            ContentUnavailableView("暂无\(item.rawValue)", systemImage: "tray")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            switch item {
            case .feeds:
                feedList(rows, for: .feeds)
            case .likes:
                feedList(likedRows, for: .likes)
            case .collections:
                ForEach(Array(userCollections.enumerated()), id: \.element.id) { idx, col in
                    CollectionRowView(item: col)
                        .onAppear {
                            if idx >= userCollections.count - 4 { Task { await loadMore(for: .collections) } }
                        }
                }
            case .following:
                ForEach(Array(following.enumerated()), id: \.element.id) { idx, user in
                    UserRowView(user: user)
                        .onAppear {
                            if idx >= following.count - 4 { Task { await loadMore(for: .following) } }
                        }
                }
            case .fans:
                ForEach(Array(followers.enumerated()), id: \.element.id) { idx, user in
                    UserRowView(user: user)
                        .onAppear {
                            if idx >= followers.count - 4 { Task { await loadMore(for: .fans) } }
                        }
                }
            }
        }
    }

    private func feedList(_ items: [HomeFeedRow], for activeTab: UserTab) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { idx, row in
            HomeRowRenderer(row: row)
                .onAppear {
                    if idx >= items.count - 4 { Task { await loadMore(for: activeTab) } }
                }
        }
    }

    private func reloadTab(_ targetTab: UserTab, force: Bool) async {
        if !force && loadedTabs.contains(targetTab) {
            return
        }
        loadingTabs.insert(targetTab)
        defer {
            loadingTabs.remove(targetTab)
            loadedTabs.insert(targetTab)
        }
        pageByTab[targetTab] = 1
        hasMoreByTab[targetTab] = true
        do {
            switch targetTab {
            case .feeds:
                let fetched = try await API.userFeeds(uid: uid, page: 1)
                guard !Task.isCancelled else { return }
                rows = fetched
                hasMoreByTab[.feeds] = !fetched.isEmpty
            case .likes:
                let fetched = try await API.userLikeFeeds(uid: uid, page: 1)
                guard !Task.isCancelled else { return }
                likedRows = fetched
                hasMoreByTab[.likes] = !fetched.isEmpty
            case .collections:
                if !appState.settings.enableCloudFavoritesLoad {
                    userCollections = []
                    hasMoreByTab[.collections] = false
                    return
                }
                let fetched = try await API.collectionList(uid: uid, page: 1)
                guard !Task.isCancelled else { return }
                userCollections = fetched
                hasMoreByTab[.collections] = !fetched.isEmpty
            case .following:
                if !appState.settings.enableCloudFollowLoad {
                    following = []
                    hasMoreByTab[.following] = false
                    return
                }
                let fetched = try await API.userList(uid: uid, followers: false, page: 1)
                guard !Task.isCancelled else { return }
                following = fetched
                hasMoreByTab[.following] = !fetched.isEmpty
            case .fans:
                if !appState.settings.enableCloudFollowLoad {
                    followers = []
                    hasMoreByTab[.fans] = false
                    return
                }
                let fetched = try await API.userList(uid: uid, followers: true, page: 1)
                guard !Task.isCancelled else { return }
                followers = fetched
                hasMoreByTab[.fans] = !fetched.isEmpty
            }
        } catch {
            guard !Task.isCancelled else { return }
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(for targetTab: UserTab) async {
        guard hasMoreByTab[targetTab] != false, !loadingTabs.contains(targetTab) else { return }
        let next = (pageByTab[targetTab] ?? 1) + 1
        do {
            switch targetTab {
            case .feeds:
                let fetched = try await API.userFeeds(uid: uid, page: next)
                var seen = Set(rows.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                rows.append(contentsOf: unique)
                hasMoreByTab[.feeds] = !unique.isEmpty
            case .likes:
                let fetched = try await API.userLikeFeeds(uid: uid, page: next)
                var seen = Set(likedRows.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                likedRows.append(contentsOf: unique)
                hasMoreByTab[.likes] = !unique.isEmpty
            case .collections:
                let fetched = try await API.collectionList(uid: uid, page: next)
                var seen = Set(userCollections.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                userCollections.append(contentsOf: unique)
                hasMoreByTab[.collections] = !unique.isEmpty
            case .following:
                let fetched = try await API.userList(uid: uid, followers: false, page: next)
                var seen = Set(following.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                following.append(contentsOf: unique)
                hasMoreByTab[.following] = !unique.isEmpty
            case .fans:
                let fetched = try await API.userList(uid: uid, followers: true, page: next)
                var seen = Set(followers.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                followers.append(contentsOf: unique)
                hasMoreByTab[.fans] = !unique.isEmpty
            }
            if hasMoreByTab[targetTab] == true { pageByTab[targetTab] = next }
        } catch {
            hasMoreByTab[targetTab] = false
        }
    }

    private func handleFollowTap(profile: UserProfile) async {
        let shouldWriteCloud = appState.accounts.isLoggedIn && appState.settings.defaultFollowTarget == .cloud
        guard shouldWriteCloud else {
            toggleLocalFollow(profile: profile)
            return
        }
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }

        let targetUID = profile.id
        let previous = profile.isFollowed
        let previousFans = profile.fansNum
        let next = !previous

        self.profile?.isFollowed = next
        self.profile?.fansNum = max(0, previousFans + (next ? 1 : -1))

        do {
            try await API.followUser(uid: targetUID, follow: next)
            if !next && appState.localFollow.contains(uid: targetUID) {
                appState.localFollow.unfollow(uid: targetUID)
            }
            appState.showToast(next ? "已同步关注至云端" : "已取消关注")
        } catch {
            self.profile?.isFollowed = previous
            self.profile?.fansNum = previousFans
            let retried = await appState.handleAPIError(error)
            if retried {
                do {
                    try await API.followUser(uid: targetUID, follow: next)
                    self.profile?.isFollowed = next
                    self.profile?.fansNum = max(0, previousFans + (next ? 1 : -1))
                    if !next && appState.localFollow.contains(uid: targetUID) {
                        appState.localFollow.unfollow(uid: targetUID)
                    }
                    appState.showToast(next ? "已同步关注至云端" : "已取消关注")
                } catch {
                    _ = await appState.handleAPIError(error)
                }
            }
        }
    }

    private func toggleLocalFollow(profile: UserProfile) {
        if appState.localFollow.contains(uid: profile.id) {
            appState.localFollow.unfollow(uid: profile.id)
            appState.showToast("已取消本机关注")
        } else {
            appState.localFollow.follow(uid: profile.id, username: profile.username, avatar: profile.avatar)
            appState.showToast("已加入本机关注")
        }
    }
}
