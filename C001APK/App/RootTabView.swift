import CoolapkKit
import SwiftUI

public struct RootTabView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var appZoomNamespace

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        TabView(selection: tabSelectionBinding) {
            Tab("首页", systemImage: "house", value: RootTab.home) {
                NavigationStack(path: $state.homeNavigationPath) {
                    HomeView()
                        .c001NativeTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("关注", systemImage: "person.2", value: RootTab.follow) {
                NavigationStack(path: $state.followNavigationPath) {
                    FollowView()
                        .c001NativeTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("刷动态", systemImage: "rectangle.stack", value: RootTab.swipe) {
                NavigationStack(path: $state.swipeNavigationPath) {
                    SwipeDeckView()
                        .c001NativeTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("我的", systemImage: "person.crop.circle", value: RootTab.profile) {
                NavigationStack(path: $state.profileNavigationPath) {
                    ProfileTabView()
                        .c001NativeTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("搜索", systemImage: "magnifyingglass", value: RootTab.search, role: .search) {
                NavigationStack(path: $state.searchNavigationPath) {
                    SearchView()
                        .c001NativeTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.zoomNamespace, appZoomNamespace)
        .environment(\.oledPureBlack, appState.settings.useOledPureBlackDarkMode)
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
        case let .user(uid, initialUsername, initialAvatar, transitionID):
            UserDetailView(uid: uid, initialUsername: initialUsername, initialAvatar: initialAvatar)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .topic(tag, transitionID):
            TopicDetailView(tag: tag)
                .c001NativeTopBar()
                .applyZoomTransition(sourceID: transitionID, in: zoomNamespace)
        case let .product(id, initialTitle, transitionID):
            ProductDetailView(productID: id, initialTitle: initialTitle)
                .c001NativeTopBar()
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
        case let .page(link, title):
            PageFeedView(link: link, title: title)
                .c001NativeTopBar()
        case let .coolpic(tag):
            CoolPicView(initialTag: tag)
                .c001NativeTopBar()
        case .messages:
            MessagesView()
                .c001NativeTopBar()
        case let .chat(ukey, uid, username, avatar):
            ChatThreadView(ukey: ukey, peerUID: uid, peerName: username, peerAvatar: avatar)
                .c001NativeTopBar()
        case .history:
            HistoryListView()
                .c001NativeTopBar()
        case .favorites:
            FavoritesListView()
                .c001NativeTopBar()
        case .localFollowList:
            LocalFollowListView()
                .c001NativeTopBar()
        case .myRecentVisits:
            UserRecentVisitsView()
                .c001NativeTopBar()
        case .myLikes:
            UserLikesListView()
                .c001NativeTopBar()
        case .myReplies:
            UserRepliesListView()
                .c001NativeTopBar()
        case .accounts:
            AccountsView()
                .c001NativeTopBar()
        case .settings:
            SettingsView()
                .c001NativeTopBar()
        case .contentFilterSettings:
            ContentFilterSettingsView()
                .c001NativeTopBar()
        case let .blacklist(isTopic):
            BlacklistView(isTopic: isTopic)
                .c001NativeTopBar()
        case .deviceIdentity:
            DeviceIdentityView()
                .c001NativeTopBar()
        case .protocolParams:
            ProtocolParamsView()
                .c001NativeTopBar()
        case .about:
            AboutView()
                .c001NativeTopBar()
        case let .web(url):
            InAppWebView(url: url)
                .c001NativeTopBar()
        }
    }
}
