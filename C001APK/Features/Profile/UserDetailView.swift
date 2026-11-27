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
    @State private var loadingMoreTabs: Set<UserTab> = []
    @State private var profileLoadFailed = false
    @State private var isTogglingFollow = false
    @State private var headerHeight: CGFloat = 104
    @State private var stripHeight: CGFloat = 52
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollOffsetByTab: [UserTab: CGFloat] = [:]
    @State private var tabTasks: [UserTab: Task<Void, Never>] = [:]

    private var showCollapsedNavToolbar: Bool {
        headerHeight > 1 && scrollOffset >= headerHeight * 0.55
    }

    private var resolvedNumericUID: String {
        if let id = profile?.id, !id.isEmpty {
            return id
        }
        return uid
    }

    private var displayTitle: String {
        if let name = profile?.username, !name.isEmpty {
            return name
        }
        if let initialUsername, !initialUsername.isEmpty {
            return initialUsername
        }
        return uid.allSatisfy(\.isNumber) ? "" : uid
    }

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
        self.initialAvatar = initialAvatar.map(coolapkNormalizedURL)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
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

                PinnedEntityHeaderOverlay(
                    scrollOffset: scrollOffset,
                    headerHeight: $headerHeight,
                    stripHeight: $stripHeight
                ) {
                    headerCard
                        .padding(.top, 10)
                } tabStrip: {
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
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showCollapsedNavToolbar, (profile != nil || initialAvatar != nil) {
                    let loginPrimary = profile?.loginTime.map { "活跃 · \(Formatting.relativeTime($0))" }
                        ?? (profile?.location.isEmpty == false ? profile!.location : "")
                    let deviceSecondary = profile?.deviceTitle.isEmpty == false
                        ? profile!.deviceTitle
                        : (profile.map { "\(Formatting.count($0.fansNum)) 粉丝" } ?? "")
                    CollapsedNavEntityToolbar(
                        avatarURL: profile?.avatar ?? initialAvatar ?? "",
                        primaryLine: loginPrimary,
                        secondaryLine: deviceSecondary,
                        isFollowed: profile.map(isFollowingUser) ?? appState.localFollow.contains(uid: resolvedNumericUID),
                        showFollowButton: profile != nil && resolvedNumericUID != appState.accounts.activeUID,
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
                            let chatTID = "user-chat-\(transitionSeed)"
                            Button {
                                appState.push(.chat(
                                    ukey: profile?.id ?? uid,
                                    uid: profile?.id ?? uid,
                                    username: profile?.username ?? initialUsername ?? "",
                                    avatar: profile?.avatar ?? initialAvatar ?? "",
                                    transitionID: chatTID
                                ))
                            } label: {
                                Image(systemName: "envelope")
                                    .applyZoomSource(id: chatTID, in: zoomNamespace, cornerRadius: 16)
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
            .animation(.easeInOut(duration: 0.18), value: showCollapsedNavToolbar)
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
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollOffset = scrollOffsetByTab[nextTab] ?? 0
                }
                startLoadTab(nextTab, force: false)
            }
            .onAppear {
                if profile == nil, let cached = appState.cachedUserProfile(uid: uid) {
                    profile = cached
                }
            }
            .task(id: uid) {
                if profile == nil, let cached = appState.cachedUserProfile(uid: uid) {
                    profile = cached
                }
                async let headerLoad: Void = reloadProfileHeader(showPromptOnCaptcha: false)
                async let tabLoad: Void = reloadTab(tab, force: !loadedTabs.contains(tab))
                _ = await (headerLoad, tabLoad)
            }
            .onDisappear {
                for task in tabTasks.values {
                    task.cancel()
                }
                tabTasks.removeAll()
            }
        }
    }

    private func startLoadTab(_ targetTab: UserTab, force: Bool) {
        tabTasks[targetTab]?.cancel()
        tabTasks[targetTab] = Task {
            if profile == nil, !uid.allSatisfy(\.isNumber) {
                await reloadProfileHeader(showPromptOnCaptcha: false)
            }
            await reloadTab(targetTab, force: force)
        }
    }

    private func tabScrollPage(for item: UserTab) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(0, headerHeight + stripHeight))
                    .id("user-top-\(item.rawValue)")
                LazyVStack(alignment: .leading, spacing: 10) {
                    tabBody(for: item)
                }
                .padding(.bottom, 88)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newOffset in
            guard item == tab else { return }
            scrollOffsetByTab[item] = newOffset
            if abs(newOffset - scrollOffset) > 0.5 || (newOffset <= 0 && scrollOffset > 0) {
                scrollOffset = newOffset
            }
        }
        .refreshable {
            await reloadProfileHeader(showPromptOnCaptcha: true)
            await reloadTab(item, force: true)
        }
    }

    private func isFollowingUser(_ profile: UserProfile) -> Bool {
        let isLocal = appState.localFollow.contains(uid: profile.id)
        let isCloud = appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad && profile.isFollowed
        return isLocal || isCloud
    }

    private var headerCard: some View {
        let effectiveProfile = profile ?? appState.cachedUserProfile(uid: uid)
        let avatarURL = (effectiveProfile?.avatar.isEmpty == false ? effectiveProfile!.avatar : (initialAvatar ?? ""))
        let shownName = effectiveProfile?.username.isEmpty == false ? effectiveProfile!.username : displayTitle

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    if !avatarURL.isEmpty {
                        appState.openMedia(
                            [FeedMedia(sourceUrl: avatarURL)],
                            at: 0,
                            sourcePrefix: "user-avatar-\(transitionSeed)"
                        )
                    }
                } label: {
                    AvatarView(url: avatarURL, size: 64)
                        .applyZoomSource(id: "user-avatar-\(transitionSeed)-0", in: zoomNamespace, cornerRadius: 32)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !shownName.isEmpty {
                            Text(shownName)
                                .font(.title3.weight(.bold))
                        }
                        if let profile {
                            Text("Lv.\(profile.level)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if let profile {
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
                    } else if profileLoadFailed {
                        Text("资料加载失败")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()

                if let profile, resolvedNumericUID != appState.accounts.activeUID {
                    followButton(profile: profile)
                } else if profileLoadFailed {
                    Button("重试") {
                        Task {
                            await reloadProfileHeader(showPromptOnCaptcha: true)
                            await reloadTab(tab, force: true)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if let profile {
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
        }
        .padding(16)
        .c001CardStyle(cornerRadius: 22)
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.2), value: profile?.id)
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
            .foregroundStyle((isCloudFollowed || isLocalFollowed) ? Color.primary : Color.white)
            .background(
                (isCloudFollowed || isLocalFollowed) ? Color(uiColor: .tertiarySystemFill) : Color.accentColor,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        (isCloudFollowed || isLocalFollowed)
                            ? Color(uiColor: .separator).opacity(0.45)
                            : Color.white.opacity(0.28),
                        lineWidth: 0.8
                    )
            }
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

    private func reloadProfileHeader(showPromptOnCaptcha: Bool) async {
        profileLoadFailed = false
        do {
            let loaded = try await API.userProfile(uid: uid)
            guard !Task.isCancelled else { return }
            appState.cacheUserProfile(loaded)
            withAnimation(.smooth(duration: 0.24)) {
                profile = loaded
            }
        } catch {
            guard !Task.isCancelled else { return }
            if profile == nil {
                profileLoadFailed = true
            }
            _ = await appState.handleAPIError(error, allowCaptchaPrompt: showPromptOnCaptcha)
        }
    }

    private func reloadTab(_ targetTab: UserTab, force: Bool) async {
        if !force && loadedTabs.contains(targetTab) {
            return
        }
        loadingTabs.insert(targetTab)
        defer {
            loadingTabs.remove(targetTab)
        }
        pageByTab[targetTab] = 1
        hasMoreByTab[targetTab] = true
        let targetUID = resolvedNumericUID
        do {
            switch targetTab {
            case .feeds:
                let fetched = try await API.userFeeds(uid: targetUID, page: 1)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    rows = fetched
                    loadedTabs.insert(targetTab)
                }
                hasMoreByTab[.feeds] = !fetched.isEmpty
            case .likes:
                let fetched = try await API.userLikeFeeds(uid: targetUID, page: 1)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    likedRows = fetched
                    loadedTabs.insert(targetTab)
                }
                hasMoreByTab[.likes] = !fetched.isEmpty
            case .collections:
                if !appState.settings.enableCloudFavoritesLoad {
                    userCollections = []
                    hasMoreByTab[.collections] = false
                    loadedTabs.insert(targetTab)
                    return
                }
                let fetched = try await API.collectionList(uid: targetUID, page: 1)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    userCollections = fetched
                    loadedTabs.insert(targetTab)
                }
                hasMoreByTab[.collections] = !fetched.isEmpty
            case .following:
                if !appState.settings.enableCloudFollowLoad {
                    following = []
                    hasMoreByTab[.following] = false
                    loadedTabs.insert(targetTab)
                    return
                }
                let fetched = try await API.userList(uid: targetUID, followers: false, page: 1)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    following = fetched
                    loadedTabs.insert(targetTab)
                }
                hasMoreByTab[.following] = !fetched.isEmpty
            case .fans:
                if !appState.settings.enableCloudFollowLoad {
                    followers = []
                    hasMoreByTab[.fans] = false
                    loadedTabs.insert(targetTab)
                    return
                }
                let fetched = try await API.userList(uid: targetUID, followers: true, page: 1)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.24)) {
                    followers = fetched
                    loadedTabs.insert(targetTab)
                }
                hasMoreByTab[.fans] = !fetched.isEmpty
            }
        } catch {
            guard !Task.isCancelled else { return }
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(for targetTab: UserTab) async {
        guard hasMoreByTab[targetTab] != false,
              !loadingTabs.contains(targetTab),
              !loadingMoreTabs.contains(targetTab) else { return }
        loadingMoreTabs.insert(targetTab)
        defer { loadingMoreTabs.remove(targetTab) }
        let next = (pageByTab[targetTab] ?? 1) + 1
        let targetUID = resolvedNumericUID
        do {
            switch targetTab {
            case .feeds:
                let fetched = try await API.userFeeds(uid: targetUID, page: next)
                var seen = Set(rows.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                rows.append(contentsOf: unique)
                hasMoreByTab[.feeds] = !unique.isEmpty
            case .likes:
                let fetched = try await API.userLikeFeeds(uid: targetUID, page: next)
                var seen = Set(likedRows.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                likedRows.append(contentsOf: unique)
                hasMoreByTab[.likes] = !unique.isEmpty
            case .collections:
                let fetched = try await API.collectionList(uid: targetUID, page: next)
                var seen = Set(userCollections.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                userCollections.append(contentsOf: unique)
                hasMoreByTab[.collections] = !unique.isEmpty
            case .following:
                let fetched = try await API.userList(uid: targetUID, followers: false, page: next)
                var seen = Set(following.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                following.append(contentsOf: unique)
                hasMoreByTab[.following] = !unique.isEmpty
            case .fans:
                let fetched = try await API.userList(uid: targetUID, followers: true, page: next)
                var seen = Set(followers.map(\.id))
                let unique = fetched.filter { seen.insert($0.id).inserted }
                followers.append(contentsOf: unique)
                hasMoreByTab[.fans] = !unique.isEmpty
            }
            if hasMoreByTab[targetTab] == true { pageByTab[targetTab] = next }
        } catch {
            _ = await appState.handleAPIError(error, allowCaptchaPrompt: false)
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
