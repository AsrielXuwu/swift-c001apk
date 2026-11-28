import CoolapkKit
import SwiftUI

public struct RootTabView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var appZoomNamespace

    public init() {}

    public var body: some View {
        @Bindable var state = appState
        let visibleTabs = appState.settings.rootTabConfig.visibleTabs

        TabView(selection: tabSelectionBinding) {
            ForEach(visibleTabs) { tab in
                if tab == .search {
                    Tab(tab.title, systemImage: tab.systemImage, value: tab, role: .search) {
                        tabNavigationStack(for: tab, state: $state)
                    }
                } else {
                    Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                        tabNavigationStack(for: tab, state: $state)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.zoomNamespace, appZoomNamespace)
        .environment(\.oledPureBlack, appState.settings.useOledPureBlackDarkMode)
        .onChange(of: visibleTabs) { _, newTabs in
            if !newTabs.contains(appState.selectedTab) {
                appState.selectedTab = newTabs.first ?? .home
            }
        }
        .sheet(isPresented: $state.showOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $state.showLoginSheet) {
            LoginSheet()
        }
        .sheet(isPresented: $state.showWebLoginSheet) {
            WebLoginSheet()
        }
        .sheet(item: $state.favoritePickerFeed) { feed in
            CollectionPickerSheet(feed: feed)
        }
        .sheet(item: $state.activeCaptchaRequest) { request in
            CaptchaWebViewSheet(challenge: request.challenge) { token in
                appState.completeCaptcha(validateToken: token)
            }
        }
        .fullScreenCover(item: $state.mediaViewer) { presentation in
            MediaViewerView(presentation: presentation)
                .environment(\.zoomNamespace, appZoomNamespace)
        }
        .overlay {
            ComposeFloatingOverlayHost(composeMode: $state.composeMode)
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.toastMessage {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: appState.toastMessage)
    }

    @ViewBuilder
    private func tabNavigationStack(for tab: RootTab, state: Bindable<AppState>) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: state.homeNavigationPath) {
                HomeView()
                    .c001NativeTopBar()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
        case .partition:
            NavigationStack(path: state.partitionNavigationPath) {
                PartitionHubView()
                    .c001NativeTopBar()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
        case .follow:
            NavigationStack(path: state.followNavigationPath) {
                FollowView()
                    .c001NativeTopBar()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
        case .swipe:
            NavigationStack(path: state.swipeNavigationPath) {
                SwipeDeckView()
                    .c001NativeTopBar()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
        case .profile:
            NavigationStack(path: state.profileNavigationPath) {
                ProfileTabView()
                    .c001NativeTopBar()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
        case .search:
            NavigationStack(path: state.searchNavigationPath) {
                SearchView()
                    .c001NativeTopBar()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
        }
    }

    private var tabSelectionBinding: Binding<RootTab> {
        Binding(
            get: { appState.selectedTab },
            set: { newTab in
                if newTab == appState.selectedTab {
                    switch newTab {
                    case .home:
                        if !appState.homeNavigationPath.isEmpty {
                            appState.homeNavigationPath.removeAll()
                        } else {
                            appState.homeDoubleTapTrigger += 1
                        }
                    case .partition:
                        appState.partitionNavigationPath.removeAll()
                    case .follow:
                        if !appState.followNavigationPath.isEmpty {
                            appState.followNavigationPath.removeAll()
                        } else {
                            appState.followDoubleTapTrigger += 1
                        }
                    case .swipe:
                        if !appState.swipeNavigationPath.isEmpty {
                            appState.swipeNavigationPath.removeAll()
                        } else {
                            appState.swipeDoubleTapTrigger += 1
                        }
                    case .profile:
                        appState.profileNavigationPath.removeAll()
                    case .search:
                        appState.searchNavigationPath.removeAll()
                    }
                } else {
                    appState.selectedTab = newTab
                }
            }
        )
    }

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        AppRouteDestinationView(route: route, zoomNamespace: appZoomNamespace)
    }
}

public struct AppRouteDestinationView: View {
    public let route: AppRoute
    public let zoomNamespace: Namespace.ID?

    public init(route: AppRoute, zoomNamespace: Namespace.ID? = nil) {
        self.route = route
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        switch route {
        case let .feed(id, initial, transitionID):
            FeedDetailView(feedID: id, initialFeed: initial)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .user(uid, initialUsername, initialAvatar, transitionID, initialTab):
            UserDetailView(uid: uid, initialUsername: initialUsername, initialAvatar: initialAvatar, initialTab: initialTab)
                .scrollEdgeEffectHidden(true, for: .top)
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .topic(tag, transitionID):
            TopicDetailView(tag: tag)
                .scrollEdgeEffectHidden(true, for: .top)
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .product(id, initialTitle, transitionID):
            ProductDetailView(productID: id, initialTitle: initialTitle)
                .scrollEdgeEffectHidden(true, for: .top)
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .app(id, initialTitle, transitionID):
            AppDetailView(appID: id, initialTitle: initialTitle)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .collection(id, initialTitle, transitionID):
            CollectionDetailView(collectionID: id, initialTitle: initialTitle)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .dyh(id, initialTitle, transitionID):
            DyhDetailView(dyhID: id, initialTitle: initialTitle)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .event(id, initial, transitionID):
            EventDetailView(eventID: id, initialEvent: initial)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .page(link, title, transitionID):
            PageFeedView(link: link, title: title)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .partitionHub(transitionID):
            PartitionHubView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .followFeed(transitionID):
            FollowView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .productCategoryBrowser(transitionID):
            ProductCategoryBrowserView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .coolpic(tag, transitionID):
            CoolPicView(initialTag: tag)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case .messages:
            MessagesView()
                .c001NativeTopBar()
        case let .chat(ukey, uid, username, avatar, transitionID):
            ChatThreadView(ukey: ukey, peerUID: uid, peerName: username, peerAvatar: avatar)
                .c001NativeTopBar()
                .toolbar(.hidden, for: .tabBar)
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .history(transitionID):
            HistoryListView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .favorites(transitionID):
            FavoritesListView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .localFollowList(transitionID):
            LocalFollowListView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .myRecentVisits(transitionID):
            UserRecentVisitsView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .myLikes(transitionID):
            UserLikesListView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .myReplies(transitionID):
            UserRepliesListView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .accounts(transitionID):
            AccountsView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .settings(transitionID):
            SettingsView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .contentFilterSettings(transitionID):
            ContentFilterSettingsView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .blacklist(isTopic, transitionID):
            BlacklistView(isTopic: isTopic)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .deviceIdentity(transitionID):
            DeviceIdentityView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .protocolParams(transitionID):
            ProtocolParamsView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .about(transitionID):
            AboutView()
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .web(url, transitionID):
            InAppWebView(url: url)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        }
    }
}
