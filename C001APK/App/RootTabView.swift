import CoolapkKit
import SwiftUI

public struct RootTabView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        TabView(selection: tabSelectionBinding) {
            Tab("首页", systemImage: "house", value: RootTab.home) {
                NavigationStack(path: $state.homeNavigationPath) {
                    HomeView()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("关注", systemImage: "person.2", value: RootTab.follow) {
                NavigationStack(path: $state.followNavigationPath) {
                    FollowView()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("消息", systemImage: "bubble.left.and.bubble.right", value: RootTab.messages) {
                NavigationStack(path: $state.messagesNavigationPath) {
                    MessagesView()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }
            .badge(appState.badge.total)

            Tab("我的", systemImage: "person.crop.circle", value: RootTab.profile) {
                NavigationStack(path: $state.profileNavigationPath) {
                    ProfileTabView()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }

            Tab("搜索", systemImage: "magnifyingglass", value: RootTab.search, role: .search) {
                NavigationStack(path: $state.searchNavigationPath) {
                    SearchView()
                        .navigationDestination(for: AppRoute.self, destination: destinationView)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
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
        .sheet(item: $state.composeMode) { mode in
            ComposeSheet(mode: mode)
        }
        .sheet(item: $state.activeCaptchaRequest) { request in
            CaptchaWebViewSheet(challenge: request.challenge) { token in
                appState.completeCaptcha(validateToken: token)
            }
        }
        .fullScreenCover(item: $state.mediaViewer) { presentation in
            MediaViewerView(presentation: presentation)
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
                    case .messages:
                        appState.messagesNavigationPath.removeAll()
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
        case let .feed(id, initial):
            FeedDetailView(feedID: id, initialFeed: initial)
        case let .user(uid):
            UserDetailView(uid: uid)
        case let .topic(tag):
            TopicDetailView(tag: tag)
        case let .product(id):
            ProductDetailView(productID: id)
        case let .app(id):
            AppDetailView(appID: id)
        case let .collection(id):
            CollectionDetailView(collectionID: id)
        case let .dyh(id):
            DyhDetailView(dyhID: id)
        case let .event(id):
            EventDetailView(eventID: id)
        case let .page(link, title):
            PageFeedView(link: link, title: title)
        case let .coolpic(tag):
            CoolPicView(initialTag: tag)
        case let .chat(ukey, uid, username, avatar):
            ChatThreadView(ukey: ukey, peerUID: uid, peerName: username, peerAvatar: avatar)
        case .history:
            HistoryListView()
        case .favorites:
            FavoritesListView()
        case .localFollowList:
            LocalFollowListView()
        case .accounts:
            AccountsView()
        case .settings:
            SettingsView()
        case .contentFilterSettings:
            ContentFilterSettingsView()
        case let .blacklist(isTopic):
            BlacklistView(isTopic: isTopic)
        case .deviceIdentity:
            DeviceIdentityView()
        case .protocolParams:
            ProtocolParamsView()
        case .about:
            AboutView()
        case let .web(url):
            InAppWebView(url: url)
        }
    }
}
