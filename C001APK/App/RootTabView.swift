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
                        .c001TransparentTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("关注", systemImage: "person.2", value: RootTab.follow) {
                NavigationStack(path: $state.followNavigationPath) {
                    FollowView()
                        .c001TransparentTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("我的", systemImage: "person.crop.circle", value: RootTab.profile) {
                NavigationStack(path: $state.profileNavigationPath) {
                    ProfileTabView()
                        .c001TransparentTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("搜索", systemImage: "magnifyingglass", value: RootTab.search, role: .search) {
                NavigationStack(path: $state.searchNavigationPath) {
                    SearchView()
                        .c001TransparentTopBar()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.zoomNamespace, appZoomNamespace)
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
        switch route {
        case let .feed(id, initial, transitionID):
            FeedDetailView(feedID: id, initialFeed: initial)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .user(uid, transitionID):
            UserDetailView(uid: uid)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .topic(tag, transitionID):
            TopicDetailView(tag: tag)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .product(id, transitionID):
            ProductDetailView(productID: id)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .app(id, transitionID):
            AppDetailView(appID: id)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .collection(id, transitionID):
            CollectionDetailView(collectionID: id)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .dyh(id, transitionID):
            DyhDetailView(dyhID: id)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .event(id, initial, transitionID):
            EventDetailView(eventID: id, initialEvent: initial)
                .c001TransparentTopBar()
                .applyZoomTransition(sourceID: transitionID, in: appZoomNamespace)
        case let .page(link, title):
            PageFeedView(link: link, title: title)
                .c001TransparentTopBar()
        case let .coolpic(tag):
            CoolPicView(initialTag: tag)
                .c001TransparentTopBar()
        case .messages:
            MessagesView()
                .c001TransparentTopBar()
        case let .chat(ukey, uid, username, avatar):
            ChatThreadView(ukey: ukey, peerUID: uid, peerName: username, peerAvatar: avatar)
                .c001TransparentTopBar()
        case .history:
            HistoryListView()
                .c001TransparentTopBar()
        case .favorites:
            FavoritesListView()
                .c001TransparentTopBar()
        case .localFollowList:
            LocalFollowListView()
                .c001TransparentTopBar()
        case .accounts:
            AccountsView()
                .c001TransparentTopBar()
        case .settings:
            SettingsView()
                .c001TransparentTopBar()
        case .contentFilterSettings:
            ContentFilterSettingsView()
                .c001TransparentTopBar()
        case let .blacklist(isTopic):
            BlacklistView(isTopic: isTopic)
                .c001TransparentTopBar()
        case .deviceIdentity:
            DeviceIdentityView()
                .c001TransparentTopBar()
        case .protocolParams:
            ProtocolParamsView()
                .c001TransparentTopBar()
        case .about:
            AboutView()
                .c001TransparentTopBar()
        case let .web(url):
            InAppWebView(url: url)
                .c001TransparentTopBar()
        }
    }
}
