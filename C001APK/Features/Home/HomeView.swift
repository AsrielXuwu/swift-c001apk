import CoolapkKit
import SwiftUI

public struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Namespace private var fallbackNamespace
    @State private var viewModel = HomeFeedViewModel()
    @State private var selectedTab: HomeTabType = .feed
    @State private var scrolledTab: HomeTabType? = .feed
    @State private var showTabEditor = false
    @State private var isFabCollapsed = false
    @State private var navAvatarSeed = UUID().uuidString

    public init() {}

    public var body: some View {
        let visibleTabs = appState.settings.homeTabConfig.visibleTabs
        let activeTab = visibleTabs.contains(selectedTab) ? selectedTab : .feed

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(visibleTabs) { tab in
                        tabContent(for: tab)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(tab)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledTab)
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 4) {
                    floatingCategoryStrip(visibleTabs: visibleTabs, activeTab: activeTab, proxy: proxy)
                    if let subCategories = viewModel.subCategoriesByTab[activeTab], !subCategories.isEmpty {
                        subCategoryStrip(categories: subCategories, for: activeTab)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !appState.settings.hideHomePublishButton {
                    publishFloatingButton
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("酷安")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let active = appState.accounts.activeAccount {
                    let avatarURL = appState.currentUserProfile?.avatar ?? active.avatar
                    let avatarID = "home-nav-avatar-\(navAvatarSeed)"
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appState.push(.user(
                                uid: active.uid,
                                initialUsername: appState.currentUserProfile?.username ?? active.displayName,
                                initialAvatar: avatarURL,
                                transitionID: avatarID
                            ))
                        } label: {
                            AvatarView(url: avatarURL, size: 28)
                        }
                        .accessibilityLabel("个人主页")
                    }
                    .matchedTransitionSource(id: avatarID, in: zoomNamespace ?? fallbackNamespace)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appState.showLoginSheet = true
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                        .accessibilityLabel("登录")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTabEditor = true
                    } label: {
                        Label("编辑分类", systemImage: "slider.horizontal.3")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        appState.push(.page(link: "/main/headline", title: "头条"))
                    } label: {
                        Label("头条", systemImage: "newspaper")
                    }

                    Button {
                        appState.push(.messages)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                            if appState.badge.total > 0 {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 3, y: -2)
                            }
                        }
                    }
                    .accessibilityLabel("消息")
                }
            }
            .sheet(isPresented: $showTabEditor) {
                HomeTabsEditorSheet()
            }
            .onChange(of: visibleTabs) { _, newTabs in
                if !newTabs.contains(selectedTab) {
                    let fallback = newTabs.first ?? .feed
                    selectedTab = fallback
                    scrolledTab = fallback
                }
            }
            .onChange(of: scrolledTab) { _, newTab in
                if let newTab, newTab != selectedTab, visibleTabs.contains(newTab) {
                    selectedTab = newTab
                }
            }
            .onChange(of: activeTab) { _, newTab in
                appState.homeSelectedTab = newTab
                if scrolledTab != newTab {
                    withAnimation(.snappy(duration: 0.25)) {
                        scrolledTab = newTab
                    }
                }
                if isFabCollapsed {
                    withAnimation(.snappy(duration: 0.22)) {
                        isFabCollapsed = false
                    }
                }
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo("tab-chip-\(newTab.rawValue)", anchor: .center)
                }
            }
            .onAppear {
                if visibleTabs.contains(appState.homeSelectedTab), selectedTab != appState.homeSelectedTab {
                    selectedTab = appState.homeSelectedTab
                    scrolledTab = appState.homeSelectedTab
                }
            }
            .task(id: "\(appState.isSessionBootstrapped)|\(appState.sessionVersion)|\(activeTab.rawValue)") {
                guard appState.isSessionBootstrapped else { return }
                await viewModel.loadInitial(tab: activeTab, appState: appState)
            }
            .onChange(of: appState.homeDoubleTapTrigger) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo("home-top-\(activeTab.rawValue)", anchor: .top)
                    isFabCollapsed = false
                }
                Task {
                    await viewModel.loadInitial(tab: activeTab, appState: appState, force: true)
                }
            }
        }
    }

    private var publishFloatingButton: some View {
        Button {
            if appState.accounts.isLoggedIn {
                appState.composeMode = .newFeed
            } else {
                appState.showLoginSheet = true
            }
        } label: {
            HStack(spacing: isFabCollapsed ? 0 : 6) {
                Image(systemName: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .frame(width: 22, height: 22)
                if !isFabCollapsed {
                    Text("发布动态")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                }
            }
            .padding(.horizontal, isFabCollapsed ? 11 : 16)
            .frame(minWidth: 44, minHeight: 44, maxHeight: 44)
            .clipShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.24), value: isFabCollapsed)
    }

    private func subCategoryStrip(categories: [HomeSection], for tab: HomeTabType) -> some View {
        let currentID = viewModel.selectedSubCategoryByTab[tab]?.id
        return ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(categories) { item in
                        let isSelected = (currentID == item.id)
                        Button {
                            Task { await viewModel.selectSubCategory(item, for: tab, appState: appState) }
                        } label: {
                            Text(item.title)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    private func floatingCategoryStrip(
        visibleTabs: [HomeTabType],
        activeTab: HomeTabType,
        proxy: ScrollViewProxy
    ) -> some View {
        FloatingTabStrip(
            items: visibleTabs,
            selection: activeTab,
            titleProvider: { $0.label },
            onSelect: { tab in
                selectedTab = tab
                scrolledTab = tab
            },
            onReselect: { tab in
                withAnimation(.snappy) {
                    proxy.scrollTo("home-top-\(tab.rawValue)", anchor: .top)
                    isFabCollapsed = false
                }
            }
        )
    }

    @ViewBuilder
    private func tabContent(for tab: HomeTabType) -> some View {
        let rows = viewModel.rowsByTab[tab] ?? []
        let isLoading = viewModel.loadingTabs.contains(tab)
        let hasLoaded = viewModel.loadedTabs.contains(tab)

        if (!hasLoaded || isLoading) && rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorByTab[tab], rows.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试") {
                    Task { await viewModel.loadInitial(tab: tab, appState: appState, force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if rows.isEmpty {
            ContentUnavailableView("暂无内容", systemImage: "tray")
        } else {
            ScrollView {
                Color.clear.frame(height: 0).id("home-top-\(tab.rawValue)")
                LazyVStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HomeRowRenderer(row: row)
                            .onAppear {
                                if index >= rows.count - 4 {
                                    Task { await viewModel.loadMore(tab: tab, appState: appState) }
                                }
                            }
                    }

                    if viewModel.loadingMoreTabs.contains(tab) {
                        ProgressView()
                            .padding(.vertical, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { oldOffset, newOffset in
                guard tab == selectedTab else { return }
                let delta = newOffset - oldOffset
                if newOffset <= 12 {
                    if isFabCollapsed { isFabCollapsed = false }
                } else if delta > 8 && newOffset > 40 {
                    if !isFabCollapsed { isFabCollapsed = true }
                } else if delta < -8 {
                    if isFabCollapsed { isFabCollapsed = false }
                }
            }
            .refreshable {
                await viewModel.loadInitial(tab: tab, appState: appState, force: true)
            }
            .scrollEdgeEffectHidden(true, for: .top)
        }
    }
}

struct HomeTabsEditorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var draftOrder: [HomeTabType] = []
    @State private var draftHidden: Set<HomeTabType> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(draftOrder) { tab in
                        HStack {
                            Image(systemName: tab == .feed ? "checkmark.circle.fill" : (draftHidden.contains(tab) ? "circle" : "checkmark.circle.fill"))
                                .foregroundStyle(tab == .feed || !draftHidden.contains(tab) ? Color.accentColor : Color.secondary)
                                .onTapGesture {
                                    guard tab != .feed else { return }
                                    if draftHidden.contains(tab) {
                                        draftHidden.remove(tab)
                                    } else {
                                        draftHidden.insert(tab)
                                    }
                                }
                            Text(tab.label)
                            Spacer()
                            if tab == .feed {
                                Text("固定显示")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onMove { indices, newOffset in
                        draftOrder.move(fromOffsets: indices, toOffset: newOffset)
                    }
                } header: {
                    Text("勾选显示分类，拖动右侧手柄调整顺序")
                }

                Section {
                    Button("恢复默认顺序") {
                        let def = HomeTabConfiguration()
                        draftOrder = def.order
                        draftHidden = def.hidden
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("编辑主页分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        appState.settings.homeTabConfig = HomeTabConfiguration(order: draftOrder, hidden: draftHidden)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                draftOrder = appState.settings.homeTabConfig.order
                draftHidden = appState.settings.homeTabConfig.hidden
            }
        }
    }
}
