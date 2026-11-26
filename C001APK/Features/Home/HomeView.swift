import CoolapkKit
import SwiftUI

public struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = HomeFeedViewModel()
    @State private var selectedTab: HomeTabType = .feed
    @State private var showTabEditor = false

    public init() {}

    public var body: some View {
        let visibleTabs = appState.settings.homeTabConfig.visibleTabs
        let activeTab = visibleTabs.contains(selectedTab) ? selectedTab : .feed

        ScrollViewReader { proxy in
            TabView(selection: $selectedTab) {
                ForEach(visibleTabs) { tab in
                    tabContent(for: tab)
                        .tag(tab)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                floatingCategoryStrip(visibleTabs: visibleTabs, activeTab: activeTab, proxy: proxy)
            }
            .navigationTitle("酷安")
            .navigationBarTitleDisplayMode(.inline)
            .c001NavBarStyle()
            .toolbar {
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

                    if !appState.settings.hideHomePublishButton {
                        Button {
                            if appState.accounts.isLoggedIn {
                                appState.composeMode = .newFeed
                            } else {
                                appState.showLoginSheet = true
                            }
                        } label: {
                            Label("发布动态", systemImage: "square.and.pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: $showTabEditor) {
                HomeTabsEditorSheet()
            }
            .onChange(of: visibleTabs) { _, newTabs in
                if !newTabs.contains(selectedTab) {
                    selectedTab = newTabs.first ?? .feed
                }
            }
            .onChange(of: activeTab) { _, newTab in
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo("tab-chip-\(newTab.rawValue)", anchor: .center)
                }
            }
            .task(id: "\(appState.sessionVersion)|\(activeTab.rawValue)") {
                await viewModel.loadInitial(tab: activeTab, appState: appState)
            }
            .onChange(of: appState.homeDoubleTapTrigger) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo("home-top-\(activeTab.rawValue)", anchor: .top)
                }
                Task {
                    await viewModel.loadInitial(tab: activeTab, appState: appState, force: true)
                }
            }
        }
    }

    private func floatingCategoryStrip(
        visibleTabs: [HomeTabType],
        activeTab: HomeTabType,
        proxy: ScrollViewProxy
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(visibleTabs) { tab in
                        let isSelected = tab == activeTab
                        Button {
                            if isSelected {
                                withAnimation(.snappy) {
                                    proxy.scrollTo("home-top-\(tab.rawValue)", anchor: .top)
                                }
                            } else {
                                withAnimation(.snappy(duration: 0.24)) {
                                    selectedTab = tab
                                }
                            }
                        } label: {
                            Text(tab.label)
                                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .id("tab-chip-\(tab.rawValue)")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: HomeTabType) -> some View {
        let rows = viewModel.rowsByTab[tab] ?? []
        let isLoading = viewModel.loadingTabs.contains(tab)

        if isLoading && rows.isEmpty {
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
                .padding(.vertical, 8)
            }
            .refreshable {
                await viewModel.loadInitial(tab: tab, appState: appState, force: true)
            }
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
