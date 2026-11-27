import CoolapkKit
import SwiftUI
import UIKit
import WebKit

private struct ChoiceChip: Identifiable, Hashable {
    let id: String
    let title: String
}

private enum SortBarExtractor {
    struct Result {
        let filteredRows: [HomeFeedRow]
        let options: [HomeSection]
        let selectedTitle: String
    }

    static func extract(from rows: [HomeFeedRow]) -> Result {
        var filtered: [HomeFeedRow] = []
        filtered.reserveCapacity(rows.count)
        var foundOptions: [HomeSection] = []
        var foundSelectedTitle = ""

        for row in rows {
            if case let .linkBar(id, links) = row, id.hasPrefix("sortbar-") {
                if foundOptions.isEmpty, !links.isEmpty {
                    foundOptions = links
                    let parts = id.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
                    if parts.count == 3 {
                        foundSelectedTitle = String(parts[2])
                    }
                }
                continue
            }
            filtered.append(row)
        }

        return Result(filteredRows: filtered, options: foundOptions, selectedTitle: foundSelectedTitle)
    }
}

// MARK: - Topic Detail

public struct TopicDetailView: View {
    public let tag: String

    @Environment(AppState.self) private var appState
    @State private var topic: TopicItem?
    @State private var activeTabID = "lastupdate_desc"
    @State private var scrolledTabID: String? = "lastupdate_desc"
    @State private var sortOptionsByTab: [String: [HomeSection]] = [:]
    @State private var selectedSortIDByTab: [String: String] = [:]
    @State private var rowsByTab: [String: [HomeFeedRow]] = [:]
    @State private var loadedTabs: Set<String> = []
    @State private var loadingTabs: Set<String> = []
    @State private var loadingMoreTabs: Set<String> = []
    @State private var pageByTab: [String: Int] = [:]
    @State private var hasMoreByTab: [String: Bool] = [:]
    @State private var isTogglingFollow = false
    @State private var headerHeight: CGFloat = 100
    @State private var stripHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollOffsetByTab: [String: CGFloat] = [:]
    @State private var hasInitialized = false
    @State private var didResolveTopicMetadata = false

    private var showCollapsedNavToolbar: Bool {
        topic != nil && headerHeight > 1 && scrollOffset >= headerHeight * 0.55
    }

    private let fallbackSortOptions: [HomeSection] = [
        HomeSection(id: "lastupdate_desc", title: "最新回复", subtitle: "lastupdate_desc", url: "", style: ""),
        HomeSection(id: "dateline_desc", title: "最新发布", subtitle: "dateline_desc", url: "", style: ""),
        HomeSection(id: "popular", title: "热门", subtitle: "popular", url: "", style: "")
    ]

    private let singleDefaultTopicTab = HomeSection(
        id: "all_topic_feeds",
        title: "讨论",
        subtitle: "lastupdate_desc",
        url: "",
        style: ""
    )

    public init(tag: String) { self.tag = tag }

    private var activeTabs: [HomeSection] {
        if let apiTabs = (topic ?? appState.cachedTopicDetail(tag: tag))?.tabs, !apiTabs.isEmpty {
            return apiTabs
        }
        if didResolveTopicMetadata {
            return [singleDefaultTopicTab]
        }
        return []
    }

    private var selectedTabItem: HomeSection {
        activeTabs.first { $0.id == activeTabID }
            ?? activeTabs.first
            ?? singleDefaultTopicTab
    }

    private func sortOptions(for tabItem: HomeSection) -> [HomeSection] {
        if let dynamic = sortOptionsByTab[tabItem.id], !dynamic.isEmpty {
            return dynamic
        }
        if tabItem.id == singleDefaultTopicTab.id || tabItem.title == "讨论" || tabItem.url.isEmpty {
            return fallbackSortOptions
        }
        return []
    }

    private var currentSortOptions: [HomeSection] {
        sortOptions(for: selectedTabItem)
    }

    private func selectedSortOption(for tabItem: HomeSection) -> HomeSection? {
        let options = sortOptions(for: tabItem)
        guard !options.isEmpty else { return nil }
        if let chosenID = selectedSortIDByTab[tabItem.id],
           let matched = options.first(where: { $0.id == chosenID }) {
            return matched
        }
        return options.first
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Group {
                if !didResolveTopicMetadata && activeTabs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZStack(alignment: .top) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach(activeTabs) { tabItem in
                                    topicFeedScrollPage(for: tabItem)
                                        .containerRelativeFrame(.horizontal)
                                        .frame(maxHeight: .infinity)
                                        .id(tabItem.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $scrolledTabID)
                        .scrollClipDisabled()

                        PinnedEntityHeaderOverlay(
                            scrollOffset: scrollOffset,
                            hasHeader: true,
                            headerHeight: $headerHeight,
                            stripHeight: $stripHeight
                        ) {
                            if let currentTopic = topic ?? appState.cachedTopicDetail(tag: tag) {
                                topicHeaderCard(currentTopic)
                                    .padding(.top, 8)
                            } else {
                                topicPlaceholderHeaderCard
                                    .padding(.top, 8)
                            }
                        } tabStrip: {
                            if activeTabs.count > 1 {
                                FloatingTabStrip(
                                    items: activeTabs,
                                    selection: selectedTabItem,
                                    titleProvider: \.title,
                                    onSelect: { option in
                                        activeTabID = option.id
                                    },
                                    onReselect: { option in
                                        withAnimation(.snappy) {
                                            proxy.scrollTo("topic-top-\(option.id)", anchor: .top)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .navigationTitle(topic?.title.isEmpty == false ? TopicItem.cleanTitle(topic!.title) : TopicItem.cleanTitle(tag))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let topic, showCollapsedNavToolbar {
                    let navLines = topicNavLines(topic)
                    CollapsedNavEntityToolbar(
                        avatarURL: topic.logo,
                        primaryLine: navLines.primary,
                        secondaryLine: navLines.secondary,
                        isFollowed: topic.isFollowed,
                        showFollowButton: true,
                        isDisabled: isTogglingFollow,
                        onTapAvatar: {
                            withAnimation(.snappy) {
                                proxy.scrollTo("topic-top-\(selectedTabItem.id)", anchor: .top)
                            }
                        },
                        onTapFollow: {
                            Task { await toggleFollow(topic) }
                        }
                    )
                }

                if !currentSortOptions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        let tab = selectedTabItem
                        let options = currentSortOptions
                        let selectedID = selectedSortOption(for: tab)?.id ?? options[0].id
                        Menu {
                            ForEach(options) { opt in
                                Button {
                                    selectedSortIDByTab[tab.id] = opt.id
                                    Task { await reloadFeeds(for: tab, force: true) }
                                } label: {
                                    HStack {
                                        Text(opt.title)
                                        if opt.id == selectedID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("排序方式")
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
            }
            .animation(.snappy(duration: 0.24), value: !currentSortOptions.isEmpty)
            .animation(.easeInOut(duration: 0.18), value: showCollapsedNavToolbar)
            .onChange(of: scrolledTabID) { _, newValue in
                if let newValue, newValue != activeTabID {
                    activeTabID = newValue
                }
            }
            .onChange(of: activeTabID) { _, newValue in
                appState.pageTabSelections["topic-\(tag)"] = newValue
                if scrolledTabID != newValue {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrolledTabID = newValue
                    }
                }
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollOffset = scrollOffsetByTab[newValue] ?? 0
                }
                if let target = activeTabs.first(where: { $0.id == newValue }) {
                    Task { await reloadFeeds(for: target, force: false) }
                }
            }
            .onAppear {
                if topic == nil, let cached = appState.cachedTopicDetail(tag: tag) {
                    topic = cached
                    didResolveTopicMetadata = true
                }
            }
            .task(id: tag) {
                if topic == nil, let cached = appState.cachedTopicDetail(tag: tag) {
                    topic = cached
                }
                guard !hasInitialized || topic == nil else { return }
                var loadedTopic = try? await API.topicDetail(tag: tag)
                if var fetched = loadedTopic {
                    if !fetched.isFollowed && (topic?.isFollowed == true || appState.isEntityKnownFollowed(kind: "topic", keys: [fetched.id, tag, fetched.title])) {
                        fetched.isFollowed = true
                    }
                    appState.cacheTopicDetail(fetched, forTag: tag)
                    loadedTopic = appState.cachedTopicDetail(tag: tag) ?? fetched
                }
                hasInitialized = (loadedTopic != nil)
                let effectiveTopic = loadedTopic ?? topic
                let resolvedTabs = (effectiveTopic?.tabs.isEmpty == false) ? effectiveTopic!.tabs : [singleDefaultTopicTab]
                let saved = appState.pageTabSelections["topic-\(tag)"]
                let initialTab: HomeSection? = if let saved, let matchedSaved = resolvedTabs.first(where: { $0.id == saved }) {
                    matchedSaved
                } else if let apiSel = effectiveTopic?.selectedTab, !apiSel.isEmpty,
                          let matchedAPI = resolvedTabs.first(where: { $0.subtitle == apiSel || $0.id == apiSel || $0.title == apiSel }) {
                    matchedAPI
                } else {
                    resolvedTabs.first
                }
                withAnimation(.smooth(duration: 0.24)) {
                    if let loadedTopic {
                        topic = loadedTopic
                    }
                    if let initialTab {
                        activeTabID = initialTab.id
                        scrolledTabID = initialTab.id
                    }
                    didResolveTopicMetadata = true
                }
                if let initialTab {
                    await reloadFeeds(for: initialTab, force: !loadedTabs.contains(initialTab.id))
                }
            }
        }
    }

    private var topicPlaceholderHeaderCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemFill))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "number")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(TopicItem.cleanTitle(tag))
                    .font(.headline)
                Text("正在加载话题信息…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .c001CardStyle(cornerRadius: 22)
        .padding(.horizontal, 12)
    }

    private func topicHeaderCard(_ topic: TopicItem) -> some View {
        HStack(spacing: 12) {
            RemoteImageView(url: topic.logo, maxPixelSize: 180)
                .frame(width: 58, height: 58)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(TopicItem.cleanTitle(topic.title)).font(.headline)
                Text(topicStatsText(topic))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !topic.description.isEmpty {
                    Text(topic.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button(topic.isFollowed ? "已关注" : "关注") {
                Task { await toggleFollow(topic) }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(topic.isFollowed ? Color.primary : Color.white)
            .background(topic.isFollowed ? Color(uiColor: .tertiarySystemFill) : Color.accentColor, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        topic.isFollowed ? Color(uiColor: .separator).opacity(0.45) : Color.white.opacity(0.28),
                        lineWidth: 0.8
                    )
            }
            .buttonStyle(.plain)
            .disabled(isTogglingFollow)
        }
        .padding(16)
        .c001CardStyle(cornerRadius: 22)
        .padding(.horizontal, 12)
    }

    private func topicFeedScrollPage(for tabItem: HomeSection) -> some View {
        let rows = rowsByTab[tabItem.id] ?? []
        let isLoadingTab = loadingTabs.contains(tabItem.id)
        let hasLoaded = loadedTabs.contains(tabItem.id)

        let hasStrip = activeTabs.count > 1
        let topInsetHeight = headerHeight + (hasStrip ? max(stripHeight, 52) : 10)

        return ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(0, topInsetHeight))
                    .id("topic-top-\(tabItem.id)")
                LazyVStack(alignment: .leading, spacing: 10) {
                    if (!hasLoaded || isLoadingTab) && rows.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if rows.isEmpty {
                        ContentUnavailableView("暂无话题动态", systemImage: "number")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= rows.count - 4 { Task { await loadMore(for: tabItem) } }
                                }
                        }
                    }
                }
                .padding(.bottom, 88)
            }
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newOffset in
            guard tabItem.id == activeTabID else { return }
            scrollOffsetByTab[tabItem.id] = newOffset
            if abs(newOffset - scrollOffset) > 0.5 || (newOffset <= 0 && scrollOffset > 0) {
                scrollOffset = newOffset
            }
        }
        .refreshable {
            if var fetched = try? await API.topicDetail(tag: tag) {
                if !fetched.isFollowed && (topic?.isFollowed == true || appState.isEntityKnownFollowed(kind: "topic", keys: [fetched.id, tag, fetched.title])) {
                    fetched.isFollowed = true
                }
                appState.cacheTopicDetail(fetched, forTag: tag)
                topic = appState.cachedTopicDetail(tag: tag) ?? fetched
            }
            await reloadFeeds(for: tabItem, force: true)
        }
    }

    private func topicNavLines(_ topic: TopicItem) -> (primary: String, secondary: String) {
        let primary: String
        if !topic.hotNumText.isEmpty {
            primary = "\(topic.hotNumText) 热度"
        } else if topic.hotNum > 0 {
            primary = "\(Formatting.count(topic.hotNum)) 热度"
        } else if topic.feedNum > 0 {
            primary = "\(Formatting.count(topic.feedNum)) 讨论"
        } else if !topic.feedNumText.isEmpty {
            primary = "\(topic.feedNumText) 讨论"
        } else {
            primary = TopicItem.cleanTitle(topic.title)
        }
        let discussPart = topic.feedNum > 0
            ? "\(Formatting.count(topic.feedNum)) 讨论"
            : (!topic.feedNumText.isEmpty ? "\(topic.feedNumText) 讨论" : "")
        let followPart = "\(Formatting.count(topic.followNum)) 关注"
        let secondary = discussPart.isEmpty || primary.contains("讨论")
            ? followPart
            : "\(discussPart) · \(followPart)"
        return (primary, secondary)
    }

    private func topicStatsText(_ topic: TopicItem) -> String {
        let primary: String
        if topic.feedNum > 0 {
            primary = "\(Formatting.count(topic.feedNum)) 讨论"
        } else if !topic.feedNumText.isEmpty {
            primary = "\(topic.feedNumText) 讨论"
        } else if !topic.hotNumText.isEmpty {
            primary = "\(topic.hotNumText) 热度"
        } else if topic.hotNum > 0 {
            primary = "\(Formatting.count(topic.hotNum)) 热度"
        } else {
            primary = "0 讨论"
        }
        return "\(primary) · \(Formatting.count(topic.followNum)) 关注"
    }

    private func reloadFeeds(for tabItem: HomeSection, force: Bool) async {
        if !force && (loadedTabs.contains(tabItem.id) || loadingTabs.contains(tabItem.id)) { return }
        loadingTabs.insert(tabItem.id)
        defer {
            loadingTabs.remove(tabItem.id)
        }
        pageByTab[tabItem.id] = 1
        hasMoreByTab[tabItem.id] = true
        let activeTag = topic?.title.isEmpty == false ? topic!.title : tag
        let chosenSort = selectedSortOption(for: tabItem)
        do {
            let fetched: [HomeFeedRow]
            if let chosenSort, !chosenSort.url.isEmpty {
                fetched = try await API.linkFeed(link: chosenSort.url, page: 1)
            } else {
                let listType = chosenSort?.id ?? "lastupdate_desc"
                fetched = try await API.topicTabFeeds(
                    tag: activeTag,
                    topicID: topic?.id,
                    tab: tabItem,
                    listType: listType,
                    page: 1
                )
            }
            let extracted = SortBarExtractor.extract(from: fetched)
            if !extracted.options.isEmpty {
                sortOptionsByTab[tabItem.id] = extracted.options
                if selectedSortIDByTab[tabItem.id] == nil,
                   !extracted.selectedTitle.isEmpty,
                   let matched = extracted.options.first(where: { $0.title == extracted.selectedTitle }) {
                    selectedSortIDByTab[tabItem.id] = matched.id
                }
            }
            withAnimation(.smooth(duration: 0.24)) {
                rowsByTab[tabItem.id] = extracted.filteredRows
                loadedTabs.insert(tabItem.id)
            }
            hasMoreByTab[tabItem.id] = !extracted.filteredRows.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(for tabItem: HomeSection) async {
        guard hasMoreByTab[tabItem.id] != false,
              !loadingTabs.contains(tabItem.id),
              !loadingMoreTabs.contains(tabItem.id) else { return }
        loadingMoreTabs.insert(tabItem.id)
        defer { loadingMoreTabs.remove(tabItem.id) }
        let next = (pageByTab[tabItem.id] ?? 1) + 1
        let activeTag = topic?.title.isEmpty == false ? topic!.title : tag
        let chosenSort = selectedSortOption(for: tabItem)
        let fetched: [HomeFeedRow]?
        if let chosenSort, !chosenSort.url.isEmpty {
            fetched = try? await API.linkFeed(link: chosenSort.url, page: next)
        } else {
            let listType = chosenSort?.id ?? "lastupdate_desc"
            fetched = try? await API.topicTabFeeds(
                tag: activeTag,
                topicID: topic?.id,
                tab: tabItem,
                listType: listType,
                page: next
            )
        }
        if let fetched {
            let cleaned = SortBarExtractor.extract(from: fetched).filteredRows
            let current = rowsByTab[tabItem.id] ?? []
            var seen = Set(current.map(\.id))
            let unique = cleaned.filter { seen.insert($0.id).inserted }
            rowsByTab[tabItem.id] = current + unique
            hasMoreByTab[tabItem.id] = !unique.isEmpty
            if !unique.isEmpty { pageByTab[tabItem.id] = next }
        }
    }

    private func toggleFollow(_ current: TopicItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        guard !isTogglingFollow else { return }
        let rawTitle = current.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTag = rawTitle.isEmpty ? tag.trimmingCharacters(in: .whitespacesAndNewlines) : rawTitle
        guard !targetTag.isEmpty else {
            appState.showToast("话题标签为空")
            return
        }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let next = !current.isFollowed
        let prevCount = current.followNum
        topic?.isFollowed = next
        if next {
            topic?.followNum += 1
        } else if (topic?.followNum ?? 0) > 0 {
            topic?.followNum -= 1
        }
        do {
            try await API.followTopic(tag: targetTag, follow: next)
            if let updated = topic {
                appState.cacheTopicDetail(updated, forTag: tag, explicitFollowChange: true)
            }
            appState.showToast(next ? "已关注话题" : "已取消关注")
        } catch {
            let msg = error.localizedDescription
            if next && (msg.contains("已经关注") || msg.contains("不能重复") || msg.contains("已关注")) {
                topic?.isFollowed = true
                topic?.followNum = prevCount
                if let updated = topic {
                    appState.cacheTopicDetail(updated, forTag: tag, explicitFollowChange: true)
                }
                appState.showToast("已关注话题")
            } else if !next && (msg.contains("未关注") || msg.contains("还没有关注")) {
                topic?.isFollowed = false
                topic?.followNum = prevCount
                if let updated = topic {
                    appState.cacheTopicDetail(updated, forTag: tag, explicitFollowChange: true)
                }
            } else {
                topic?.isFollowed = !next
                topic?.followNum = prevCount
                _ = await appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - Product Detail

public struct ProductDetailView: View {
    public let productID: String
    public let initialTitle: String?

    @Environment(AppState.self) private var appState
    @State private var product: ProductItem?
    @State private var apiTabs: [HomeSection] = []
    @State private var activeTabID = "lastupdate_desc"
    @State private var scrolledTabID: String? = "lastupdate_desc"
    @State private var sortOptionsByTab: [String: [HomeSection]] = [:]
    @State private var selectedSortIDByTab: [String: String] = [:]
    @State private var rowsByTab: [String: [HomeFeedRow]] = [:]
    @State private var loadedTabs: Set<String> = []
    @State private var loadingTabs: Set<String> = []
    @State private var loadingMoreTabs: Set<String> = []
    @State private var pageByTab: [String: Int] = [:]
    @State private var hasMoreByTab: [String: Bool] = [:]
    @State private var isLoadingHeader = true
    @State private var isTogglingFollow = false
    @State private var headerHeight: CGFloat = 112
    @State private var stripHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollOffsetByTab: [String: CGFloat] = [:]
    @State private var hasInitialized = false
    @State private var didResolveProductTabs = false

    private var showCollapsedNavToolbar: Bool {
        product != nil && headerHeight > 1 && scrollOffset >= headerHeight * 0.55
    }
    @State private var productVariants: [ProductConfigVariant] = []
    @State private var productSpecs: [ProductSpecEntry] = []
    @State private var variantSpecSectionsByID: [String: [ProductSpecSection]] = [:]
    @State private var loadingVariantSpecIDs: Set<String> = []
    @State private var selectedVariantID: String = ""
    @State private var isLoadingSpecs = false

    private let fallbackTabs: [ChoiceChip] = [
        ChoiceChip(id: "all_product_feeds", title: "讨论"),
        ChoiceChip(id: "__specs__", title: "参数")
    ]

    private let fallbackSortOptions: [HomeSection] = [
        HomeSection(id: "lastupdate_desc", title: "最新回复", subtitle: "lastupdate_desc", url: "", style: ""),
        HomeSection(id: "dateline_desc", title: "最新发布", subtitle: "dateline_desc", url: "", style: ""),
        HomeSection(id: "popular", title: "热门讨论", subtitle: "popular", url: "", style: "")
    ]

    public init(productID: String, initialTitle: String? = nil) {
        self.productID = productID
        self.initialTitle = initialTitle
    }

    private func isConfigTab(id: String, title: String) -> Bool {
        let lowerID = id.lowercased()
        return id == "__specs__"
            || title.contains("参数")
            || title.contains("配置")
            || lowerID.contains("config")
            || lowerID.contains("param")
    }

    private var activeChips: [ChoiceChip] {
        let effectiveTabs = !apiTabs.isEmpty ? apiTabs : (product?.tabs ?? appState.cachedProductDetail(id: productID)?.tabs ?? [])
        if !effectiveTabs.isEmpty {
            var base = effectiveTabs.map { ChoiceChip(id: $0.url, title: $0.title) }
            if !base.contains(where: { isConfigTab(id: $0.id, title: $0.title) }) {
                base.append(ChoiceChip(id: "__specs__", title: "参数"))
            }
            return base
        }
        if didResolveProductTabs {
            return fallbackTabs
        }
        return []
    }

    private var selectedChip: ChoiceChip {
        activeChips.first { $0.id == activeTabID }
            ?? activeChips.first
            ?? fallbackTabs[0]
    }

    private func sortOptions(for chip: ChoiceChip) -> [HomeSection] {
        if isConfigTab(id: chip.id, title: chip.title) { return [] }
        if let dynamic = sortOptionsByTab[chip.id], !dynamic.isEmpty {
            return dynamic
        }
        if chip.title == "讨论" || chip.id == "all_product_feeds" || apiTabs.isEmpty {
            return fallbackSortOptions
        }
        return []
    }

    private var currentSortOptions: [HomeSection] {
        sortOptions(for: selectedChip)
    }

    private func selectedSortOption(for tabID: String) -> HomeSection? {
        guard let chip = activeChips.first(where: { $0.id == tabID }) else { return nil }
        let options = sortOptions(for: chip)
        guard !options.isEmpty else { return nil }
        if let chosenID = selectedSortIDByTab[tabID],
           let matched = options.first(where: { $0.id == chosenID }) {
            return matched
        }
        return options.first
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Group {
                if !didResolveProductTabs && activeChips.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ZStack(alignment: .top) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach(activeChips) { chip in
                                    productFeedPage(for: chip)
                                        .containerRelativeFrame(.horizontal)
                                        .frame(maxHeight: .infinity)
                                        .id(chip.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $scrolledTabID)
                        .scrollClipDisabled()

                        PinnedEntityHeaderOverlay(
                            scrollOffset: scrollOffset,
                            hasHeader: product != nil || appState.cachedProductDetail(id: productID) != nil || (initialTitle?.isEmpty == false),
                            headerHeight: $headerHeight,
                            stripHeight: $stripHeight
                        ) {
                            if let currentProduct = product ?? appState.cachedProductDetail(id: productID) {
                                productHeaderCard(currentProduct)
                                    .padding(.top, 8)
                            } else if let initialTitle, !initialTitle.isEmpty {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(.secondarySystemFill))
                                        .frame(width: 60, height: 60)
                                        .overlay {
                                            Image(systemName: "iphone")
                                                .font(.title3.weight(.semibold))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(initialTitle).font(.headline)
                                        Text("正在加载数码详情…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                }
                                .padding(16)
                                .c001CardStyle(cornerRadius: 22)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                            }
                        } tabStrip: {
                            if !activeChips.isEmpty {
                                FloatingTabStrip(
                                    items: activeChips,
                                    selection: selectedChip,
                                    titleProvider: \.title,
                                    onSelect: { chip in
                                        activeTabID = chip.id
                                    },
                                    onReselect: { chip in
                                        withAnimation(.snappy) {
                                            proxy.scrollTo("product-top-\(chip.id)", anchor: .top)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .navigationTitle(product?.title.isEmpty == false ? product!.title : (initialTitle ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let product, showCollapsedNavToolbar {
                    let line1 = [
                        product.score.isEmpty ? nil : "评分 \(product.score)",
                        product.priceText.isEmpty ? nil : product.priceText
                    ].compactMap { $0 }.joined(separator: " · ")
                    let line2 = "\(Formatting.count(product.followNum)) 关注"
                        + (product.feedNum > 0 ? " · \(Formatting.count(product.feedNum)) 讨论" : "")
                    CollapsedNavEntityToolbar(
                        avatarURL: product.logo,
                        primaryLine: line1.isEmpty ? product.subtitle : line1,
                        secondaryLine: line2,
                        isFollowed: product.isFollowed,
                        showFollowButton: true,
                        isDisabled: isTogglingFollow,
                        onTapAvatar: {
                            withAnimation(.snappy) {
                                proxy.scrollTo("product-top-\(activeTabID)", anchor: .top)
                            }
                        },
                        onTapFollow: {
                            Task { await toggleFollow(product) }
                        }
                    )
                }

                if !currentSortOptions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        let chip = selectedChip
                        let options = currentSortOptions
                        let selectedID = selectedSortOption(for: chip.id)?.id ?? options[0].id
                        Menu {
                            ForEach(options) { opt in
                                Button {
                                    selectedSortIDByTab[chip.id] = opt.id
                                    Task { await reloadFeeds(for: chip.id, force: true) }
                                } label: {
                                    HStack {
                                        Text(opt.title)
                                        if opt.id == selectedID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("排序方式")
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
            }
            .animation(.snappy(duration: 0.24), value: !currentSortOptions.isEmpty)
            .animation(.easeInOut(duration: 0.18), value: showCollapsedNavToolbar)
            .onChange(of: scrolledTabID) { _, newValue in
                if let newValue, newValue != activeTabID {
                    activeTabID = newValue
                }
            }
            .onChange(of: activeTabID) { _, newValue in
                appState.pageTabSelections["product-\(productID)"] = newValue
                if scrolledTabID != newValue {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrolledTabID = newValue
                    }
                }
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollOffset = scrollOffsetByTab[newValue] ?? 0
                }
                if didResolveProductTabs {
                    Task { await reloadFeeds(for: newValue, force: false) }
                }
            }
            .onAppear {
                if product == nil, let cached = appState.cachedProductDetail(id: productID) {
                    product = cached
                    if !cached.tabs.isEmpty { apiTabs = cached.tabs }
                    didResolveProductTabs = true
                }
            }
            .task(id: productID) {
                if product == nil, let cached = appState.cachedProductDetail(id: productID) {
                    product = cached
                    if !cached.tabs.isEmpty { apiTabs = cached.tabs }
                }
                guard !hasInitialized || product == nil else { return }
                hasInitialized = true
                await reloadAll()
            }
        }
    }

    private func productFeedPage(for chip: ChoiceChip) -> some View {
        let rows = rowsByTab[chip.id] ?? []
        let isLoadingTab = loadingTabs.contains(chip.id)
        let hasLoaded = loadedTabs.contains(chip.id)
        let isSpecsTab = isConfigTab(id: chip.id, title: chip.title)

        let hasStrip = activeChips.count > 1
        let baseHeader = (product != nil || appState.cachedProductDetail(id: productID) != nil || (initialTitle?.isEmpty == false)) ? headerHeight : 0
        let topInsetHeight = baseHeader + (hasStrip ? max(stripHeight, 52) : 10)

        return ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(0, topInsetHeight))
                    .id("product-top-\(chip.id)")
                LazyVStack(alignment: .leading, spacing: 10) {
                    if isSpecsTab {
                        productSpecsSection()
                    } else if (!hasLoaded || isLoadingTab) && rows.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if rows.isEmpty {
                        ContentUnavailableView("暂无该机型动态", systemImage: "iphone")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= rows.count - 4 { Task { await loadMore(for: chip.id) } }
                                }
                        }
                    }
                }
                .padding(.bottom, 88)
            }
        }
        .scrollEdgeEffectHidden(true, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, newOffset in
            guard chip.id == activeTabID else { return }
            scrollOffsetByTab[chip.id] = newOffset
            if abs(newOffset - scrollOffset) > 0.5 || (newOffset <= 0 && scrollOffset > 0) {
                scrollOffset = newOffset
            }
        }
        .refreshable {
            await reloadAll()
        }
    }

    private func productHeaderCard(_ product: ProductItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RemoteImageView(url: product.logo, maxPixelSize: 180)
                    .frame(width: 60, height: 60)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.title).font(.headline)
                    let stats = [
                        product.score.isEmpty ? nil : "评分 \(product.score)",
                        "\(Formatting.count(product.followNum)) 关注",
                        product.feedNum > 0 ? "\(Formatting.count(product.feedNum)) 讨论" : nil
                    ].compactMap { $0 }.joined(separator: " · ")
                    Text(stats)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !product.priceText.isEmpty || !product.releaseTime.isEmpty {
                        let meta = [product.priceText, product.releaseTime].filter { !$0.isEmpty }.joined(separator: " · ")
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 8)
                Button(product.isFollowed ? "已关注" : "关注") {
                    Task { await toggleFollow(product) }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(product.isFollowed ? Color.primary : Color.white)
                .background(product.isFollowed ? Color(uiColor: .tertiarySystemFill) : Color.accentColor, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            product.isFollowed ? Color(uiColor: .separator).opacity(0.45) : Color.white.opacity(0.28),
                            lineWidth: 0.8
                        )
                }
                .buttonStyle(.plain)
                .disabled(isTogglingFollow)
            }

            if !product.recommendReason.isEmpty {
                Text(product.recommendReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !product.description.isEmpty {
                Text(FeedHTMLParser.plainText(product.description))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(16)
        .c001CardStyle(cornerRadius: 22)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func productSpecsSection() -> some View {
        let variants = !productVariants.isEmpty ? productVariants : (product?.configVariants ?? [])
        let activeVariant = variants.first { $0.id == selectedVariantID } ?? variants.first
        let generalSpecs = !productSpecs.isEmpty ? productSpecs : (product?.specEntries ?? [])
        let activeSections = activeVariant.flatMap { variantSpecSectionsByID[$0.id] } ?? []
        let isLoadingActiveVariant = activeVariant.map { loadingVariantSpecIDs.contains($0.id) } ?? false

        if isLoadingSpecs && variants.isEmpty && generalSpecs.isEmpty {
            ProgressView("正在加载版本配置与参数…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if variants.isEmpty && generalSpecs.isEmpty {
            ContentUnavailableView("暂无公开参数与版本配置", systemImage: "cpu")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !variants.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("版本配置")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(variants) { variant in
                                    let isSelected = activeVariant?.id == variant.id
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            selectedVariantID = variant.id
                                        }
                                        Task { await loadVariantSpecsIfNeeded(variant.id) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(variant.title)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                            if !variant.priceText.isEmpty {
                                                Text(variant.priceText)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if let activeVariant {
                            VStack(alignment: .leading, spacing: 6) {
                                if !activeVariant.priceText.isEmpty {
                                    specRow(label: "参考价格", value: activeVariant.priceText)
                                }
                                if !activeVariant.releaseTime.isEmpty {
                                    specRow(label: "发布日期", value: activeVariant.releaseTime)
                                }
                                if !activeVariant.keywords.isEmpty {
                                    specRow(label: "配置要点", value: activeVariant.keywords)
                                }
                                if !activeVariant.description.isEmpty {
                                    specRow(label: "版本说明", value: FeedHTMLParser.plainText(activeVariant.description))
                                }
                                ForEach(activeVariant.specs) { item in
                                    specRow(label: item.label, value: item.value)
                                }
                            }
                            .padding(.top, 4)
                            .task(id: activeVariant.id) {
                                await loadVariantSpecsIfNeeded(activeVariant.id)
                            }
                        }
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 22)
                    .padding(.horizontal, 12)

                    if isLoadingActiveVariant && activeSections.isEmpty {
                        ProgressView("正在加载该版本详细参数…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }

                    ForEach(activeSections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)

                            ForEach(Array(section.items.enumerated()), id: \.element.id) { idx, entry in
                                let showGroup = !entry.group.isEmpty && (idx == 0 || section.items[idx - 1].group != entry.group)
                                if showGroup {
                                    Text(entry.group)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.top, idx == 0 ? 0 : 6)
                                }
                                specRow(label: entry.label, value: entry.value)
                            }
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 22)
                        .padding(.horizontal, 12)
                    }
                }

                if !generalSpecs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("详细规格")
                            .font(.headline)
                        ForEach(generalSpecs) { entry in
                            specRow(label: entry.label, value: entry.value)
                        }
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 22)
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private func specRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private func reloadAll() async {
        isLoadingHeader = true
        var detail = try? await API.productDetail(id: productID)
        if var fetched = detail {
            if !fetched.isFollowed && (product?.isFollowed == true || appState.isEntityKnownFollowed(kind: "product", keys: [productID, fetched.id, fetched.title])) {
                fetched.isFollowed = true
            }
            appState.cacheProductDetail(fetched)
            detail = appState.cachedProductDetail(id: fetched.id) ?? fetched
        }
        withAnimation(.smooth(duration: 0.24)) {
            if let detail {
                product = detail
            }
            isLoadingHeader = false
        }
        if let detail {
            if !detail.configVariants.isEmpty {
                productVariants = detail.configVariants
                if selectedVariantID.isEmpty, let firstVar = detail.configVariants.first?.id {
                    selectedVariantID = firstVar
                }
            }
            if !detail.specEntries.isEmpty {
                productSpecs = detail.specEntries
            }
            if !detail.tabs.isEmpty {
                apiTabs = detail.tabs
            }
        }
        let resolvedChoices: [ChoiceChip] = {
            var base: [ChoiceChip] = !apiTabs.isEmpty
                ? apiTabs.map { ChoiceChip(id: $0.url, title: $0.title) }
                : fallbackTabs
            if !base.contains(where: { isConfigTab(id: $0.id, title: $0.title) }) {
                base.append(ChoiceChip(id: "__specs__", title: "参数"))
            }
            return base
        }()
        let saved = appState.pageTabSelections["product-\(productID)"]
        if let saved, resolvedChoices.contains(where: { $0.id == saved }) {
            activeTabID = saved
            scrolledTabID = saved
        } else if !resolvedChoices.contains(where: { $0.id == activeTabID }),
                  let first = resolvedChoices.first?.id {
            activeTabID = first
            scrolledTabID = first
        }
        didResolveProductTabs = true
        await reloadFeeds(for: activeTabID, force: true)
    }

    private func reloadFeeds(for tabID: String, force: Bool) async {
        if !force && (loadedTabs.contains(tabID) || loadingTabs.contains(tabID)) { return }
        let chipTitle = activeChips.first(where: { $0.id == tabID })?.title ?? ""
        if isConfigTab(id: tabID, title: chipTitle) {
            isLoadingSpecs = true
            let variants = !productVariants.isEmpty ? productVariants : (product?.configVariants ?? [])
            if variants.isEmpty || productSpecs.isEmpty {
                let result = await API.productConfig(productID: productID, tabURL: tabID == "__specs__" ? nil : tabID)
                if productVariants.isEmpty && !result.variants.isEmpty {
                    productVariants = result.variants
                    if selectedVariantID.isEmpty, let firstID = result.variants.first?.id {
                        selectedVariantID = firstID
                    }
                }
                if !result.specs.isEmpty {
                    var merged = productSpecs
                    for s in result.specs where !merged.contains(where: { $0.label == s.label }) {
                        merged.append(s)
                    }
                    productSpecs = merged
                }
            }
            let targetVariantID = !selectedVariantID.isEmpty ? selectedVariantID : (productVariants.first?.id ?? "")
            if !targetVariantID.isEmpty {
                await loadVariantSpecsIfNeeded(targetVariantID)
            }
            isLoadingSpecs = false
            loadedTabs.insert(tabID)
            hasMoreByTab[tabID] = false
            return
        }

        loadingTabs.insert(tabID)
        defer {
            loadingTabs.remove(tabID)
        }
        pageByTab[tabID] = 1
        hasMoreByTab[tabID] = true
        let chosenSort = selectedSortOption(for: tabID)
        let tabURL: String? = (apiTabs.isEmpty || tabID == "all_product_feeds") ? nil : tabID
        let sort = chosenSort?.id ?? "lastupdate_desc"
        do {
            let fetched: [HomeFeedRow]
            if let chosenSort, !chosenSort.url.isEmpty {
                fetched = try await API.linkFeed(link: chosenSort.url, page: 1)
            } else {
                fetched = try await API.productFeeds(
                    productID: productID,
                    title: product?.title ?? "",
                    tabURL: chosenSort != nil ? nil : tabURL,
                    listType: sort,
                    page: 1
                )
            }
            let extracted = SortBarExtractor.extract(from: fetched)
            if !extracted.options.isEmpty {
                sortOptionsByTab[tabID] = extracted.options
                if selectedSortIDByTab[tabID] == nil,
                   !extracted.selectedTitle.isEmpty,
                   let matched = extracted.options.first(where: { $0.title == extracted.selectedTitle }) {
                    selectedSortIDByTab[tabID] = matched.id
                }
            }
            withAnimation(.smooth(duration: 0.24)) {
                rowsByTab[tabID] = extracted.filteredRows
                loadedTabs.insert(tabID)
            }
            hasMoreByTab[tabID] = !extracted.filteredRows.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(for tabID: String) async {
        let chipTitle = activeChips.first(where: { $0.id == tabID })?.title ?? ""
        guard !isConfigTab(id: tabID, title: chipTitle) else { return }
        guard hasMoreByTab[tabID] != false,
              !loadingTabs.contains(tabID),
              !loadingMoreTabs.contains(tabID) else { return }
        loadingMoreTabs.insert(tabID)
        defer { loadingMoreTabs.remove(tabID) }
        let next = (pageByTab[tabID] ?? 1) + 1
        let chosenSort = selectedSortOption(for: tabID)
        let tabURL: String? = (apiTabs.isEmpty || tabID == "all_product_feeds") ? nil : tabID
        let sort = chosenSort?.id ?? "lastupdate_desc"
        let fetched: [HomeFeedRow]?
        if let chosenSort, !chosenSort.url.isEmpty {
            fetched = try? await API.linkFeed(link: chosenSort.url, page: next)
        } else {
            fetched = try? await API.productFeeds(
                productID: productID,
                title: product?.title ?? "",
                tabURL: chosenSort != nil ? nil : tabURL,
                listType: sort,
                page: next
            )
        }
        if let fetched {
            let cleaned = SortBarExtractor.extract(from: fetched).filteredRows
            let current = rowsByTab[tabID] ?? []
            var seen = Set(current.map(\.id))
            let unique = cleaned.filter { seen.insert($0.id).inserted }
            rowsByTab[tabID] = current + unique
            hasMoreByTab[tabID] = !unique.isEmpty
            if !unique.isEmpty { pageByTab[tabID] = next }
        }
    }

    private func loadVariantSpecsIfNeeded(_ variantID: String) async {
        guard !variantID.isEmpty,
              !variantID.hasPrefix("cfg-"),
              variantSpecSectionsByID[variantID] == nil,
              !loadingVariantSpecIDs.contains(variantID) else {
            return
        }
        loadingVariantSpecIDs.insert(variantID)
        defer { loadingVariantSpecIDs.remove(variantID) }
        let fetched = await API.productConfigInfo(configID: variantID)
        variantSpecSectionsByID[variantID] = fetched
    }

    private func toggleFollow(_ current: ProductItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let next = !current.isFollowed
        let prevCount = current.followNum
        product?.isFollowed = next
        if next {
            product?.followNum += 1
        } else if (product?.followNum ?? 0) > 0 {
            product?.followNum -= 1
        }
        do {
            try await API.followProduct(id: current.id, follow: next)
            if let updated = product {
                appState.cacheProductDetail(updated, explicitFollowChange: true)
            }
            appState.showToast(next ? "已关注机型" : "已取消关注")
        } catch {
            let msg = error.localizedDescription
            if next && (msg.contains("已经关注") || msg.contains("不能重复") || msg.contains("已关注")) {
                product?.isFollowed = true
                product?.followNum = prevCount
                if let updated = product {
                    appState.cacheProductDetail(updated, explicitFollowChange: true)
                }
                appState.showToast("已关注机型")
            } else if !next && (msg.contains("未关注") || msg.contains("还没有关注")) {
                product?.isFollowed = false
                product?.followNum = prevCount
                if let updated = product {
                    appState.cacheProductDetail(updated, explicitFollowChange: true)
                }
            } else {
                product?.isFollowed = !next
                product?.followNum = prevCount
                _ = await appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - App Detail

public struct AppDetailView: View {
    public let appID: String
    public let initialTitle: String?

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var app: AppItem?
    @State private var comments: [HomeFeedRow] = []
    @State private var sortMode = "lastupdate_desc"
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var page = 1
    @State private var hasMore = true

    public init(appID: String, initialTitle: String? = nil) {
        self.appID = appID
        self.initialTitle = initialTitle
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("app-top")
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let app {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                RemoteImageView(url: app.logo, maxPixelSize: 200)
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.title).font(.title3.weight(.semibold))
                                    let metaParts = [app.version, app.size, app.developer].filter { !$0.isEmpty }
                                    if !metaParts.isEmpty {
                                        Text(metaParts.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    HStack(spacing: 8) {
                                        if !app.score.isEmpty {
                                            Label("\(app.score) 分", systemImage: "star.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.orange)
                                        }
                                        let followLabel = app.followNum > 0
                                            ? "\(Formatting.count(app.followNum)) 关注"
                                            : (!app.followCount.isEmpty ? "\(app.followCount) 关注" : "")
                                        if !followLabel.isEmpty {
                                            Text(followLabel)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer(minLength: 8)
                                Button(app.isFollowed ? "已关注" : "关注") {
                                    Task { await toggleFollow(app) }
                                }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .foregroundStyle(app.isFollowed ? Color.primary : Color.white)
                                .background(
                                    app.isFollowed ? Color(uiColor: .tertiarySystemFill) : Color.accentColor,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(
                                            app.isFollowed
                                                ? Color(uiColor: .separator).opacity(0.45)
                                                : Color.white.opacity(0.28),
                                            lineWidth: 0.8
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(isTogglingFollow)
                            }

                            if !app.screenshots.isEmpty {
                                let shotPrefix = "appshots-\(transitionSeed)"
                                let shotMedia = app.screenshots.map { FeedMedia(sourceUrl: $0) }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(Array(app.screenshots.enumerated()), id: \.offset) { idx, url in
                                            Button {
                                                appState.openMedia(shotMedia, at: idx, sourcePrefix: shotPrefix)
                                            } label: {
                                                RemoteImageView(url: url, maxPixelSize: 540)
                                                    .frame(width: 140, height: 240)
                                                    .clipped()
                                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                    .overlay {
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                                    }
                                                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                    .applyZoomSource(id: "\(shotPrefix)-\(idx)", in: zoomNamespace, cornerRadius: 14)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            if !app.description.isEmpty {
                                Text(FeedHTMLParser.plainText(app.description))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 22)
                        .padding(.horizontal, 12)
                        .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                    }

                    if (!hasLoaded || isLoading) && comments.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if comments.isEmpty {
                        ContentUnavailableView("暂无应用评价", systemImage: "bubble.right")
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(Array(comments.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= comments.count - 4 { Task { await loadMore() } }
                                }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, offset in
                let progress = min(1, max(0, (offset - 36) / 70))
                if abs(progress - compactNavProgress) > 0.02 {
                    withAnimation(.easeOut(duration: 0.16)) {
                        compactNavProgress = progress
                    }
                }
            }
            .refreshable {
                await reload()
            }
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .navigationTitle(app?.title.isEmpty == false ? app!.title : (initialTitle ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let app, compactNavProgress > 0.08 {
                    let primaryText = !app.score.isEmpty ? "\(app.score) 分" : (app.version.isEmpty ? app.title : app.version)
                    let secondaryText = app.followNum > 0
                        ? "\(Formatting.count(app.followNum)) 关注"
                        : (!app.downloadCount.isEmpty ? "\(app.downloadCount) 下载" : "应用")
                    CollapsedNavEntityToolbar(
                        avatarURL: app.logo,
                        primaryLine: primaryText,
                        secondaryLine: secondaryText,
                        isFollowed: app.isFollowed,
                        showFollowButton: true,
                        isDisabled: isTogglingFollow,
                        onTapAvatar: {
                            withAnimation(.snappy) { proxy.scrollTo("app-top", anchor: .top) }
                        },
                        onTapFollow: {
                            Task { await toggleFollow(app) }
                        }
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let sortOptions: [(id: String, title: String)] = [
                        ("lastupdate_desc", "最近回复"),
                        ("dateline_desc", "最新发布"),
                        ("popular", "热度排序")
                    ]
                    Menu {
                        ForEach(sortOptions, id: \.id) { opt in
                            Button {
                                if sortMode != opt.id {
                                    sortMode = opt.id
                                    Task { await reloadComments() }
                                }
                            } label: {
                                HStack {
                                    Text(opt.title)
                                    if sortMode == opt.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("排序方式")
                }
            }
            .onAppear {
                if app == nil, let cached = appState.cachedAppDetail(id: appID) {
                    app = cached
                }
            }
            .task(id: appID) {
                if app == nil, let cached = appState.cachedAppDetail(id: appID) {
                    app = cached
                }
                await reload()
            }
        }
    }

    private var effectiveCommentAppID: String {
        if let id = app?.id, !id.isEmpty, id != "0" {
            return id
        }
        return appID
    }

    private func reload() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        page = 1
        var loadedApp = try? await API.appDetail(id: appID)
        if var fetched = loadedApp {
            if !fetched.isFollowed && (app?.isFollowed == true || appState.isEntityKnownFollowed(kind: "app", keys: [appID, fetched.id, fetched.packageName, fetched.title])) {
                fetched.isFollowed = true
            }
            appState.cacheAppDetail(fetched)
            loadedApp = appState.cachedAppDetail(id: fetched.id) ?? fetched
        }
        let targetCommentID = (loadedApp?.id.isEmpty == false && loadedApp?.id != "0") ? loadedApp!.id : effectiveCommentAppID
        let loadedComments = (try? await API.appComments(id: targetCommentID, page: 1, listType: sortMode)) ?? []
        withAnimation(.smooth(duration: 0.24)) {
            if let loadedApp { app = loadedApp }
            comments = loadedComments
        }
        hasMore = !comments.isEmpty
    }

    private func reloadComments() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        page = 1
        hasMore = true
        let targetID = effectiveCommentAppID
        do {
            let fetched = try await API.appComments(id: targetID, page: 1, listType: sortMode)
            withAnimation(.snappy(duration: 0.22)) {
                comments = fetched
            }
            hasMore = !fetched.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        let targetID = effectiveCommentAppID
        if let fetched = try? await API.appComments(id: targetID, page: next, listType: sortMode) {
            var seen = Set(comments.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            comments.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }

    private func toggleFollow(_ current: AppItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let next = !current.isFollowed
        let prevCount = current.followNum
        let targetID = (!current.id.isEmpty && current.id != "0") ? current.id : appID
        withAnimation(.snappy(duration: 0.2)) {
            app?.isFollowed = next
            if next {
                app?.followNum += 1
            } else if (app?.followNum ?? 0) > 0 {
                app?.followNum -= 1
            }
        }
        do {
            try await API.followApp(id: targetID, follow: next)
            if let updated = app {
                appState.cacheAppDetail(updated, explicitFollowChange: true)
            }
            appState.showToast(next ? "已关注应用" : "已取消关注")
        } catch {
            let msg = error.localizedDescription
            if next && (msg.contains("已经关注") || msg.contains("不能重复") || msg.contains("已关注")) {
                withAnimation(.snappy(duration: 0.2)) {
                    app?.isFollowed = true
                    app?.followNum = prevCount
                }
                if let updated = app {
                    appState.cacheAppDetail(updated, explicitFollowChange: true)
                }
                appState.showToast("已关注应用")
            } else if !next && (msg.contains("未关注") || msg.contains("还没有关注")) {
                withAnimation(.snappy(duration: 0.2)) {
                    app?.isFollowed = false
                    app?.followNum = prevCount
                }
                if let updated = app {
                    appState.cacheAppDetail(updated, explicitFollowChange: true)
                }
            } else {
                withAnimation(.snappy(duration: 0.2)) {
                    app?.isFollowed = !next
                    app?.followNum = prevCount
                }
                _ = await appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - Dyh (看看号)

public struct DyhDetailView: View {
    public let dyhID: String
    public let initialTitle: String?

    @Environment(AppState.self) private var appState
    @State private var dyh: DyhItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var page = 1
    @State private var hasMore = true

    public init(dyhID: String, initialTitle: String? = nil) {
        self.dyhID = dyhID
        self.initialTitle = initialTitle
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("dyh-top")
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let dyh {
                        HStack(spacing: 12) {
                            RemoteImageView(url: dyh.logo, maxPixelSize: 180)
                                .frame(width: 56, height: 56)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dyh.title).font(.headline)
                                Text(dyh.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button(dyh.isFollowed ? "已订阅" : "订阅") {
                                Task { await toggleFollow(dyh) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .foregroundStyle(dyh.isFollowed ? Color.primary : Color.white)
                            .background(dyh.isFollowed ? Color(uiColor: .tertiarySystemFill) : Color.accentColor, in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        dyh.isFollowed ? Color(uiColor: .separator).opacity(0.45) : Color.white.opacity(0.28),
                                        lineWidth: 0.8
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(isTogglingFollow)
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 22)
                        .padding(.horizontal, 12)
                        .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                    }

                    if (!hasLoaded || isLoading) && rows.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if rows.isEmpty {
                        ContentUnavailableView("暂无看看号文章", systemImage: "newspaper")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= rows.count - 4 { Task { await loadMore() } }
                                }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, offset in
                let progress = min(1, max(0, (offset - 36) / 70))
                if abs(progress - compactNavProgress) > 0.02 {
                    withAnimation(.easeOut(duration: 0.16)) {
                        compactNavProgress = progress
                    }
                }
            }
            .refreshable {
                await reload()
            }
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .navigationTitle(dyh?.title.isEmpty == false ? dyh!.title : (initialTitle ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let dyh, compactNavProgress > 0.08 {
                    CollapsedNavEntityToolbar(
                        avatarURL: dyh.logo,
                        primaryLine: "\(Formatting.count(dyh.followNum)) 订阅",
                        secondaryLine: dyh.likeNum > 0 ? "\(Formatting.count(dyh.likeNum)) 获赞" : "看看号",
                        isFollowed: dyh.isFollowed,
                        showFollowButton: true,
                        isDisabled: isTogglingFollow,
                        onTapAvatar: {
                            withAnimation(.snappy) { proxy.scrollTo("dyh-top", anchor: .top) }
                        },
                        onTapFollow: {
                            Task { await toggleFollow(dyh) }
                        }
                    )
                }
            }
            .onAppear {
                if dyh == nil, let cached = appState.cachedDyhDetail(id: dyhID) {
                    dyh = cached
                }
            }
            .task(id: dyhID) {
                if dyh == nil, let cached = appState.cachedDyhDetail(id: dyhID) {
                    dyh = cached
                }
                await reload()
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        page = 1
        async let detailTask = try? API.dyhDetail(id: dyhID)
        async let rowsTask = (try? API.dyhArticles(id: dyhID, page: 1)) ?? []
        var loadedDyh = await detailTask
        let loadedRows = await rowsTask
        if var fetched = loadedDyh {
            if !fetched.isFollowed && (dyh?.isFollowed == true || appState.isEntityKnownFollowed(kind: "dyh", keys: [dyhID, fetched.id, fetched.title])) {
                fetched.isFollowed = true
            }
            appState.cacheDyhDetail(fetched)
            loadedDyh = appState.cachedDyhDetail(id: fetched.id) ?? fetched
        }
        withAnimation(.smooth(duration: 0.24)) {
            if let loadedDyh { dyh = loadedDyh }
            rows = loadedRows
        }
        hasMore = !rows.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        if let fetched = try? await API.dyhArticles(id: dyhID, page: next) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }

    private func toggleFollow(_ current: DyhItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let next = !current.isFollowed
        let targetID = (!current.id.isEmpty && current.id != "0") ? current.id : dyhID
        withAnimation(.snappy(duration: 0.2)) {
            dyh?.isFollowed = next
            if next {
                dyh?.followNum += 1
            } else if (dyh?.followNum ?? 0) > 0 {
                dyh?.followNum -= 1
            }
        }
        do {
            try await API.followDyh(id: targetID, follow: next)
            if let updated = dyh {
                appState.cacheDyhDetail(updated, explicitFollowChange: true)
            }
            appState.showToast(next ? "已订阅" : "已取消订阅")
        } catch {
            let msg = error.localizedDescription
            if next && (msg.contains("已经关注") || msg.contains("不能重复") || msg.contains("已关注") || msg.contains("已订阅")) {
                withAnimation(.snappy(duration: 0.2)) {
                    dyh?.isFollowed = true
                }
                if let updated = dyh {
                    appState.cacheDyhDetail(updated, explicitFollowChange: true)
                }
                appState.showToast("已订阅")
            } else if !next && (msg.contains("未关注") || msg.contains("还没有关注") || msg.contains("未订阅")) {
                withAnimation(.snappy(duration: 0.2)) {
                    dyh?.isFollowed = false
                }
                if let updated = dyh {
                    appState.cacheDyhDetail(updated, explicitFollowChange: true)
                }
            } else {
                withAnimation(.snappy(duration: 0.2)) {
                    dyh?.isFollowed = !next
                    if next, (dyh?.followNum ?? 0) > 0 {
                        dyh?.followNum -= 1
                    } else if !next {
                        dyh?.followNum += 1
                    }
                }
                _ = await appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - Collection (收藏夹)

public struct CollectionDetailView: View {
    public let collectionID: String
    public let initialTitle: String?

    @Environment(AppState.self) private var appState
    @State private var collection: CollectionItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var page = 1
    @State private var hasMore = true

    public init(collectionID: String, initialTitle: String? = nil) {
        self.collectionID = collectionID
        self.initialTitle = initialTitle
    }

    private var isLocalOnlyRoute: Bool {
        collectionID.hasPrefix("local:")
    }

    private var effectiveTitle: String {
        if let colTitle = collection?.title, !colTitle.isEmpty { return colTitle }
        if let initialTitle, !initialTitle.isEmpty { return initialTitle }
        if let lf = matchedLocalFolder { return lf.title }
        return "收藏夹"
    }

    private var matchedLocalFolder: LocalCollectionFolder? {
        if isLocalOnlyRoute {
            let localID = String(collectionID.dropFirst("local:".count))
            return appState.historyAndFav.folders.first { $0.id == localID }
        }
        if let byID = appState.historyAndFav.folders.first(where: { $0.id == collectionID }) {
            return byID
        }
        let targetNorm = HistoryAndFavStore.normalizedFolderTitle(collection?.title ?? initialTitle ?? "")
        guard !targetNorm.isEmpty else { return nil }
        return appState.historyAndFav.folders.first {
            HistoryAndFavStore.normalizedFolderTitle($0.title) == targetNorm
        }
    }

    private var matchingLocalEntries: [LocalFavoriteEntry] {
        let targetNorm = HistoryAndFavStore.normalizedFolderTitle(effectiveTitle)
        let localFolderID = matchedLocalFolder?.id
        return appState.historyAndFav.favorites.filter { entry in
            guard !entry.resolvedIsCloudSynced else { return false }
            if let localFolderID, entry.resolvedCollectionID == localFolderID {
                return true
            }
            if !isLocalOnlyRoute && entry.resolvedCollectionID == collectionID {
                return true
            }
            if !targetNorm.isEmpty,
               let folder = appState.historyAndFav.folders.first(where: { $0.id == entry.resolvedCollectionID }),
               HistoryAndFavStore.normalizedFolderTitle(folder.title) == targetNorm {
                return true
            }
            return false
        }
    }

    private var cloudFeedIDSet: Set<String> {
        var ids = Set<String>()
        for row in rows {
            if case let .feed(feed) = row, !feed.id.isEmpty {
                ids.insert(feed.id)
            }
        }
        return ids
    }

    private var localFeedByID: [String: LocalFavoriteEntry] {
        var dict: [String: LocalFavoriteEntry] = [:]
        for entry in matchingLocalEntries where dict[entry.id] == nil {
            dict[entry.id] = entry
        }
        return dict
    }

    private var localOnlyEntries: [LocalFavoriteEntry] {
        let cIDs = cloudFeedIDSet
        return matchingLocalEntries.filter { !cIDs.contains($0.id) }
    }

    public var body: some View {
        let localEntries = matchingLocalEntries
        let localOnly = localOnlyEntries
        let localMap = localFeedByID
        let hasLocalFolder = matchedLocalFolder != nil || !localEntries.isEmpty
        let hasCloudFolder = !isLocalOnlyRoute && (collection != nil || !rows.isEmpty)

        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("col-top")
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let collection {
                        HStack(spacing: 12) {
                            if !collection.logo.isEmpty {
                                RemoteImageView(url: collection.logo, maxPixelSize: 180)
                                    .frame(width: 56, height: 56)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.blue.opacity(0.14))
                                    .frame(width: 56, height: 56)
                                    .overlay {
                                        Image(systemName: hasLocalFolder ? "folder.fill.badge.person.crop" : "icloud.fill")
                                            .font(.title3)
                                            .foregroundStyle(Color.blue)
                                    }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(collection.title).font(.headline)
                                    if hasLocalFolder {
                                        SourceOriginBadge(isCloud: false)
                                    }
                                    SourceOriginBadge(isCloud: true)
                                }
                                let cloudCount = max(collection.itemNum, cloudFeedIDSet.count)
                                let statText = hasLocalFolder
                                    ? "本地 \(localEntries.count) 条 · 云端 \(cloudCount) 项 · \(Formatting.count(collection.followNum)) 关注"
                                    : "\(cloudCount) 项 · \(Formatting.count(collection.followNum)) 关注"
                                Text(statText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(collection.isFollowed ? "已关注" : "关注") {
                                Task { await toggleFollow(collection) }
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .foregroundStyle(collection.isFollowed ? Color.primary : Color.white)
                            .background(collection.isFollowed ? Color(uiColor: .tertiarySystemFill) : Color.accentColor, in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        collection.isFollowed ? Color(uiColor: .separator).opacity(0.45) : Color.white.opacity(0.28),
                                        lineWidth: 0.8
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(isTogglingFollow)
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 22)
                        .padding(.horizontal, 12)
                        .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                    } else if hasLocalFolder {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Image(systemName: "bookmark.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(effectiveTitle).font(.headline)
                                    SourceOriginBadge(isCloud: false)
                                    if hasCloudFolder {
                                        SourceOriginBadge(isCloud: true)
                                    }
                                }
                                Text("本地 \(localEntries.count) 条收藏")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 22)
                        .padding(.horizontal, 12)
                        .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                    }

                    if (!hasLoaded || isLoading) && rows.isEmpty && localOnly.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if rows.isEmpty && localOnly.isEmpty {
                        ContentUnavailableView("暂无收藏内容", systemImage: "star")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ForEach(localOnly) { entry in
                            StoredFeedCardRow(
                                feedID: entry.id,
                                snapshot: entry.feed,
                                fallbackTitle: entry.title,
                                fallbackPreview: entry.preview,
                                fallbackUsername: entry.username,
                                fallbackAvatar: entry.avatar,
                                fallbackDate: entry.savedAt,
                                badgeIsCloud: false,
                                showBothBadges: false,
                                deleteTitle: "取消本机收藏",
                                onDelete: {
                                    appState.historyAndFav.removeFavorite(id: entry.id)
                                }
                            )
                        }

                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            Group {
                                if case let .feed(feed) = row {
                                    let alsoInLocal = localMap[feed.id] != nil || appState.historyAndFav.isLocallyFavorited(id: feed.id)
                                    FeedRowView(
                                        feed: feed,
                                        originBadgeIsCloud: true,
                                        showBothOriginBadges: alsoInLocal,
                                        contextDeleteTitle: alsoInLocal ? "取消本机收藏" : nil,
                                        onContextDelete: alsoInLocal ? {
                                            appState.historyAndFav.removeFavorite(id: feed.id)
                                        } : nil
                                    )
                                } else {
                                    HomeRowRenderer(row: row)
                                }
                            }
                            .onAppear {
                                if idx >= rows.count - 4 { Task { await loadMore() } }
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, offset in
                let progress = min(1, max(0, (offset - 36) / 70))
                if abs(progress - compactNavProgress) > 0.02 {
                    withAnimation(.easeOut(duration: 0.16)) {
                        compactNavProgress = progress
                    }
                }
            }
            .refreshable {
                await reload()
            }
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .navigationTitle(effectiveTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let collection, compactNavProgress > 0.08 {
                    CollapsedNavEntityToolbar(
                        avatarURL: collection.logo,
                        primaryLine: "\(max(collection.itemNum, cloudFeedIDSet.count) + localOnly.count) 项内容",
                        secondaryLine: "\(Formatting.count(collection.followNum)) 关注",
                        isFollowed: collection.isFollowed,
                        showFollowButton: true,
                        isDisabled: isTogglingFollow,
                        onTapAvatar: {
                            withAnimation(.snappy) { proxy.scrollTo("col-top", anchor: .top) }
                        },
                        onTapFollow: {
                            Task { await toggleFollow(collection) }
                        }
                    )
                }
            }
            .onAppear {
                if !isLocalOnlyRoute, collection == nil, let cached = appState.cachedCollectionDetail(id: collectionID) {
                    collection = cached
                }
            }
            .task(id: collectionID) {
                if !isLocalOnlyRoute, collection == nil, let cached = appState.cachedCollectionDetail(id: collectionID) {
                    collection = cached
                }
                await reload()
            }
        }
    }

    private func reload() async {
        if isLocalOnlyRoute {
            isLoading = false
            hasLoaded = true
            hasMore = false
            return
        }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        page = 1
        async let detailTask = try? API.collectionDetail(id: collectionID)
        async let itemsTask = (try? API.collectionItems(id: collectionID, page: 1)) ?? []
        var loadedCol = await detailTask
        let loadedItems = await itemsTask
        if var fetched = loadedCol {
            if !fetched.isFollowed && (collection?.isFollowed == true || appState.isEntityKnownFollowed(kind: "collection", keys: [collectionID, fetched.id, fetched.title])) {
                fetched.isFollowed = true
            }
            appState.cacheCollectionDetail(fetched)
            loadedCol = appState.cachedCollectionDetail(id: fetched.id) ?? fetched
        }
        withAnimation(.smooth(duration: 0.24)) {
            if let loadedCol { collection = loadedCol }
            rows = loadedItems
        }
        hasMore = !rows.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        if let fetched = try? await API.collectionItems(id: collectionID, page: next) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }

    private func toggleFollow(_ current: CollectionItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        let next = !current.isFollowed
        let prevCount = current.followNum
        collection?.isFollowed = next
        if next {
            collection?.followNum += 1
        } else if (collection?.followNum ?? 0) > 0 {
            collection?.followNum -= 1
        }
        do {
            try await API.followCollection(id: collectionID, follow: next)
            if let updated = collection {
                appState.cacheCollectionDetail(updated, explicitFollowChange: true)
            }
            appState.showToast(next ? "已关注收藏夹" : "已取消关注")
        } catch {
            let msg = error.localizedDescription
            if next && (msg.contains("已经关注") || msg.contains("不能重复") || msg.contains("已关注")) {
                collection?.isFollowed = true
                collection?.followNum = prevCount
                if let updated = collection {
                    appState.cacheCollectionDetail(updated, explicitFollowChange: true)
                }
                appState.showToast("已关注收藏夹")
            } else if !next && (msg.contains("未关注") || msg.contains("还没有关注")) {
                collection?.isFollowed = false
                collection?.followNum = prevCount
                if let updated = collection {
                    appState.cacheCollectionDetail(updated, explicitFollowChange: true)
                }
            } else {
                collection?.isFollowed = !next
                collection?.followNum = prevCount
                _ = await appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - Event Detail

public struct EventDetailView: View {
    public let eventID: String
    public let initialEvent: EventItem?

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var event: EventItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var page = 1
    @State private var hasMore = true
    @State private var coverRatio: CGFloat?

    public init(eventID: String, initialEvent: EventItem? = nil) {
        self.eventID = eventID
        self.initialEvent = initialEvent
        self._event = State(initialValue: initialEvent)
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let event {
                    VStack(alignment: .leading, spacing: 12) {
                        if !event.cover.isEmpty {
                            let coverPrefix = "event-cover-\(transitionSeed)"
                            let coverMedia = FeedMedia(sourceUrl: event.cover)
                            let resolvedRatio = max(0.55, min(coverRatio ?? MediaGridView.inferredAspectRatio(from: event.cover) ?? 1.85, 2.8))
                            RemoteImageView(url: event.cover, maxPixelSize: 1200, contentMode: .fit) { size in
                                guard size.width > 0, size.height > 0 else { return }
                                let r = size.width / size.height
                                if abs((coverRatio ?? 0) - r) > 0.01 {
                                    coverRatio = r
                                }
                            }
                            .aspectRatio(resolvedRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 340)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .applyZoomSource(id: "\(coverPrefix)-0", in: zoomNamespace, cornerRadius: 16)
                            .onTapGesture {
                                appState.openMedia([coverMedia], at: 0, sourcePrefix: coverPrefix)
                            }
                        }

                        HStack(spacing: 8) {
                            if !event.title.isEmpty {
                                Text(event.title)
                                    .font(.title3.weight(.bold))
                            }
                            Spacer()
                            if !event.statusText.isEmpty {
                                Text(event.statusText)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.16), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        let meta = [
                            event.startTimeText,
                            event.joinNum > 0 ? "\(Formatting.count(event.joinNum)) 人参与" : ""
                        ].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !event.description.isEmpty {
                            RichTextView(
                                html: event.description,
                                fontSize: 15 * appState.settings.fontScale,
                                showEmoji: appState.settings.showEmoji
                            ) { link in
                                appState.openRawLink(link)
                            }
                        }

                        if let webURL = resolvedWebURL(from: event) {
                            Button {
                                appState.push(.web(url: webURL))
                            } label: {
                                Label("在应用内查看完整活动页", systemImage: "safari")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 20)
                    .padding(.horizontal, 12)
                }

                if (!hasLoaded || isLoading) && rows.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else if rows.isEmpty && event == nil {
                    ContentUnavailableView("暂无活动内容", systemImage: "calendar.badge.exclamationmark")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if !rows.isEmpty {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        HomeRowRenderer(row: row)
                            .onAppear {
                                if idx >= rows.count - 4 { Task { await loadMore() } }
                            }
                    }
                } else {
                    ContentUnavailableView("暂无更多活动动态", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(.vertical, 12)
        }
        .refreshable {
            await reload()
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .bottom)
        .c001PageBackground()
        .navigationTitle(event?.title.isEmpty == false ? event!.title : "活动详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: eventID) {
            await reload()
        }
    }

    private func resolvedWebURL(from event: EventItem) -> URL? {
        if let direct = URL(string: event.url), direct.scheme == "http" || direct.scheme == "https" {
            return direct
        }
        if !event.id.isEmpty, event.id.allSatisfy(\.isNumber) {
            return URL(string: "https://www.coolapk.com/event/\(event.id)")
        }
        return nil
    }

    private func reload() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        page = 1
        async let detailTask = try? API.eventDetail(id: eventID)
        async let feedsTask = (try? API.eventFeeds(id: eventID, page: 1)) ?? []
        if let fetched = await detailTask, (!fetched.title.isEmpty || !fetched.description.isEmpty || !fetched.cover.isEmpty) {
            event = fetched
        }
        rows = await feedsTask
        hasMore = !rows.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        if let fetched = try? await API.eventFeeds(id: eventID, page: next) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }
}

// MARK: - Generic Page / CoolPic / InAppWebView

public struct PageFeedView: View {
    public let link: String
    public let title: String

    @Environment(AppState.self) private var appState
    @State private var subTabs: [HomeSection] = []
    @State private var selectedTabID: String = ""
    @State private var scrolledTabID: String?
    @State private var sortOptionsByTab: [String: [HomeSection]] = [:]
    @State private var selectedSortIDByTab: [String: String] = [:]
    @State private var rowsByTab: [String: [HomeFeedRow]] = [:]
    @State private var loadedTabs: Set<String> = []
    @State private var loadingTabs: Set<String> = []
    @State private var loadingMoreTabs: Set<String> = []
    @State private var pageByTab: [String: Int] = [:]
    @State private var hasMoreByTab: [String: Bool] = [:]
    @State private var hasInitialized = false
    @State private var didResolveInitialLayout = false

    public init(link: String, title: String) {
        self.link = link
        self.title = title
    }

    private var activeTab: HomeSection {
        subTabs.first { $0.id == selectedTabID }
            ?? subTabs.first
            ?? HomeSection(id: link, title: title, subtitle: "", url: link, style: "")
    }

    private var activeTabKey: String {
        subTabs.isEmpty ? link : activeTab.id
    }

    private var currentSortOptions: [HomeSection] {
        sortOptionsByTab[activeTabKey] ?? []
    }

    private func selectedSortOption(for tabID: String) -> HomeSection? {
        let options = sortOptionsByTab[tabID] ?? []
        guard !options.isEmpty else { return nil }
        if let chosenID = selectedSortIDByTab[tabID],
           let matched = options.first(where: { $0.id == chosenID }) {
            return matched
        }
        return options.first
    }

    public var body: some View {
        ScrollViewReader { proxy in
            Group {
                if !didResolveInitialLayout && subTabs.isEmpty && (rowsByTab[link]?.isEmpty ?? true) {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if subTabs.isEmpty {
                    singlePageScrollView(tabID: link, tabURL: link)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(subTabs) { item in
                                singlePageScrollView(tabID: item.id, tabURL: item.url)
                                    .containerRelativeFrame(.horizontal)
                                    .frame(maxHeight: .infinity)
                                    .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrolledTabID)
                    .safeAreaBar(edge: .top, spacing: 0) {
                        FloatingTabStrip(
                            items: subTabs,
                            selection: activeTab,
                            titleProvider: \.title,
                            onSelect: { item in
                                selectedTabID = item.id
                            },
                            onReselect: { item in
                                withAnimation(.snappy) {
                                    proxy.scrollTo("page-top-\(item.id)", anchor: .top)
                                }
                            }
                        )
                    }
                }
            }
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !currentSortOptions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        let tabID = activeTabKey
                        let tabURL = subTabs.isEmpty ? link : activeTab.url
                        let options = currentSortOptions
                        let selectedID = selectedSortOption(for: tabID)?.id ?? options[0].id
                        Menu {
                            ForEach(options) { opt in
                                Button {
                                    selectedSortIDByTab[tabID] = opt.id
                                    Task { await loadSubTab(tabID: tabID, url: tabURL, force: true) }
                                } label: {
                                    HStack {
                                        Text(opt.title)
                                        if opt.id == selectedID {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("排序方式")
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
            }
            .animation(.snappy(duration: 0.24), value: !currentSortOptions.isEmpty)
            .onChange(of: scrolledTabID) { _, newValue in
                if let newValue, newValue != selectedTabID {
                    selectedTabID = newValue
                }
            }
            .onChange(of: selectedTabID) { _, newID in
                if !newID.isEmpty {
                    appState.pageTabSelections["page-\(link)"] = newID
                }
                if scrolledTabID != newID {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrolledTabID = newID
                    }
                }
                if didResolveInitialLayout,
                   let tab = subTabs.first(where: { $0.id == newID }) {
                    Task { await loadSubTab(tabID: tab.id, url: tab.url, force: false) }
                }
            }
            .task(id: link) {
                guard !hasInitialized || (subTabs.isEmpty && (rowsByTab[link]?.isEmpty ?? true)) else { return }
                hasInitialized = true
                await loadInitial()
            }
        }
    }

    @ViewBuilder
    private func singlePageScrollView(tabID: String, tabURL: String) -> some View {
        let rows = rowsByTab[tabID] ?? []
        let hasLoaded = loadedTabs.contains(tabID)
        let isLoadingTab = loadingTabs.contains(tabID)

        if (!hasLoaded || isLoadingTab) && rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView("暂无内容", systemImage: "tray")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("page-top-\(tabID)")
                    LazyVStack(spacing: 10) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= rows.count - 4 { Task { await loadMore(tabID: tabID, url: tabURL) } }
                                }
                        }
                    }
                    .padding(.bottom, 88)
                }
            }
            .refreshable {
                if subTabs.isEmpty || tabURL == link {
                    await loadInitial()
                } else {
                    await loadSubTab(tabID: tabID, url: tabURL, force: true)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private func applySortExtraction(_ rawRows: [HomeFeedRow], for tabID: String) -> [HomeFeedRow] {
        let extracted = SortBarExtractor.extract(from: rawRows)
        if !extracted.options.isEmpty {
            sortOptionsByTab[tabID] = extracted.options
            if selectedSortIDByTab[tabID] == nil,
               !extracted.selectedTitle.isEmpty,
               let matched = extracted.options.first(where: { $0.title == extracted.selectedTitle }) {
                selectedSortIDByTab[tabID] = matched.id
            }
        }
        return filterNonTabRows(extracted.filteredRows)
    }

    private func loadInitial() async {
        loadingTabs.insert(link)
        defer {
            loadingTabs.remove(link)
            didResolveInitialLayout = true
        }
        do {
            let initial: [HomeFeedRow]
            let isHistoryLink = link.contains("recentHistory") || link.contains("hitHistory")
            if isHistoryLink && !appState.settings.enableCloudHistoryLoad {
                initial = appState.historyAndFav.history.compactMap { entry in
                    entry.feed.map { HomeFeedRow.feed($0) }
                }
            } else if link == "/main/headline" {
                initial = try await API.headlineFeed(page: 1)
            } else {
                initial = try await API.linkFeed(link: link, page: 1)
            }
            loadedTabs.insert(link)
            let extractedTabs = extractSubTabs(from: initial)
            if !extractedTabs.isEmpty {
                let initialSortResult = SortBarExtractor.extract(from: initial)
                let contentOnly = filterNonTabRows(initialSortResult.filteredRows)
                var resolvedTabs = extractedTabs
                let preferredSavedID = appState.pageTabSelections["page-\(link)"]
                if !contentOnly.isEmpty {
                    let existingIdx = resolvedTabs.firstIndex { tab in
                        normalizedComparisonKey(tab.url) == normalizedComparisonKey(link)
                    }
                    if let existingIdx {
                        let firstTab = resolvedTabs[existingIdx]
                        subTabs = resolvedTabs
                        if !initialSortResult.options.isEmpty {
                            sortOptionsByTab[firstTab.id] = initialSortResult.options
                            if selectedSortIDByTab[firstTab.id] == nil,
                               !initialSortResult.selectedTitle.isEmpty,
                               let matched = initialSortResult.options.first(where: { $0.title == initialSortResult.selectedTitle }) {
                                selectedSortIDByTab[firstTab.id] = matched.id
                            }
                        }
                        rowsByTab[firstTab.id] = contentOnly
                        loadedTabs.insert(firstTab.id)
                        pageByTab[firstTab.id] = 1
                        hasMoreByTab[firstTab.id] = true
                        let targetID = (preferredSavedID.flatMap { saved in
                            resolvedTabs.contains(where: { $0.id == saved }) ? saved : nil
                        }) ?? (resolvedTabs.contains(where: { $0.id == selectedTabID }) ? selectedTabID : firstTab.id)
                        selectedTabID = targetID
                        scrolledTabID = targetID
                        appState.pageTabSelections["page-\(link)"] = targetID
                        didResolveInitialLayout = true
                        if targetID != firstTab.id, let targetTab = resolvedTabs.first(where: { $0.id == targetID }) {
                            await loadSubTab(tabID: targetTab.id, url: targetTab.url, force: false)
                        }
                    } else {
                        let originTab = HomeSection(
                            id: "origin-\(link)",
                            title: title.isEmpty ? "默认" : title,
                            subtitle: "",
                            url: link,
                            style: ""
                        )
                        resolvedTabs.insert(originTab, at: 0)
                        subTabs = resolvedTabs
                        if !initialSortResult.options.isEmpty {
                            sortOptionsByTab[originTab.id] = initialSortResult.options
                            if selectedSortIDByTab[originTab.id] == nil,
                               !initialSortResult.selectedTitle.isEmpty,
                               let matched = initialSortResult.options.first(where: { $0.title == initialSortResult.selectedTitle }) {
                                selectedSortIDByTab[originTab.id] = matched.id
                            }
                        }
                        rowsByTab[originTab.id] = contentOnly
                        loadedTabs.insert(originTab.id)
                        pageByTab[originTab.id] = 1
                        hasMoreByTab[originTab.id] = true
                        let targetID = (preferredSavedID.flatMap { saved in
                            resolvedTabs.contains(where: { $0.id == saved }) ? saved : nil
                        }) ?? (resolvedTabs.contains(where: { $0.id == selectedTabID }) ? selectedTabID : originTab.id)
                        selectedTabID = targetID
                        scrolledTabID = targetID
                        appState.pageTabSelections["page-\(link)"] = targetID
                        didResolveInitialLayout = true
                        if targetID != originTab.id, let targetTab = resolvedTabs.first(where: { $0.id == targetID }) {
                            await loadSubTab(tabID: targetTab.id, url: targetTab.url, force: false)
                        }
                    }
                } else {
                    subTabs = resolvedTabs
                    let targetTab = preferredSavedID.flatMap { saved in
                        resolvedTabs.first(where: { $0.id == saved })
                    } ?? resolvedTabs.first(where: { $0.id == selectedTabID }) ?? resolvedTabs.first
                    if let targetTab {
                        selectedTabID = targetTab.id
                        scrolledTabID = targetTab.id
                        appState.pageTabSelections["page-\(link)"] = targetTab.id
                        didResolveInitialLayout = true
                        await loadSubTab(tabID: targetTab.id, url: targetTab.url, force: false)
                    }
                }
            } else {
                subTabs = []
                selectedTabID = link
                let cleaned = applySortExtraction(initial, for: link)
                rowsByTab[link] = cleaned
                pageByTab[link] = 1
                hasMoreByTab[link] = !cleaned.isEmpty
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadSubTab(tabID: String, url: String, force: Bool) async {
        if !force && (loadedTabs.contains(tabID) || loadingTabs.contains(tabID)) { return }
        loadingTabs.insert(tabID)
        defer {
            loadingTabs.remove(tabID)
        }
        pageByTab[tabID] = 1
        let chosenSort = selectedSortOption(for: tabID)
        let effectiveURL = (chosenSort?.url.isEmpty == false) ? chosenSort!.url : url
        do {
            let fetched: [HomeFeedRow]
            if effectiveURL == "/main/headline" {
                fetched = try await API.headlineFeed(page: 1)
            } else {
                fetched = try await API.linkFeed(link: effectiveURL, page: 1)
            }
            let filtered = applySortExtraction(fetched, for: tabID)
            rowsByTab[tabID] = filtered
            hasMoreByTab[tabID] = !filtered.isEmpty
            loadedTabs.insert(tabID)
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(tabID: String, url: String) async {
        guard hasMoreByTab[tabID] != false,
              !loadingTabs.contains(tabID),
              !loadingMoreTabs.contains(tabID) else { return }
        loadingMoreTabs.insert(tabID)
        defer { loadingMoreTabs.remove(tabID) }
        let next = (pageByTab[tabID] ?? 1) + 1
        let chosenSort = selectedSortOption(for: tabID)
        let effectiveURL = (chosenSort?.url.isEmpty == false) ? chosenSort!.url : url
        let fetched: [HomeFeedRow]?
        if effectiveURL == "/main/headline" {
            fetched = try? await API.headlineFeed(page: next)
        } else {
            fetched = try? await API.linkFeed(link: effectiveURL, page: next)
        }
        if let fetched {
            let filtered = filterNonTabRows(SortBarExtractor.extract(from: fetched).filteredRows)
            let current = rowsByTab[tabID] ?? []
            var seen = Set(current.map(\.id))
            let unique = filtered.filter { seen.insert($0.id).inserted }
            rowsByTab[tabID] = current + unique
            hasMoreByTab[tabID] = !unique.isEmpty
            if !unique.isEmpty { pageByTab[tabID] = next }
        }
    }

    private func normalizedComparisonKey(_ raw: String) -> String {
        API.pageTarget(from: raw).trimmingCharacters(in: CharacterSet(charactersIn: "/# "))
    }

    private func extractSubTabs(from items: [HomeFeedRow]) -> [HomeSection] {
        for item in items {
            switch item {
            case let .linkBar(id, sections):
                if !id.hasPrefix("sortbar-"), !sections.isEmpty { return sections }
            case let .columnTabs(_, sections):
                if !sections.isEmpty { return sections }
            default:
                continue
            }
        }
        return []
    }

    private func filterNonTabRows(_ items: [HomeFeedRow]) -> [HomeFeedRow] {
        items.filter { row in
            switch row {
            case .linkBar, .columnTabs: return false
            default: return true
            }
        }
    }
}

public struct CoolPicView: View {
    public let initialTag: String

    @Environment(AppState.self) private var appState
    @State private var sortType = "recommend"
    @State private var scrolledSort: String? = "recommend"
    @State private var rowsBySort: [String: [HomeFeedRow]] = [:]
    @State private var loadedSorts: Set<String> = []
    @State private var loadingSorts: Set<String> = []
    @State private var loadingMoreSorts: Set<String> = []
    @State private var errorBySort: [String: String] = [:]
    @State private var pageBySort: [String: Int] = [:]
    @State private var hasMoreBySort: [String: Bool] = [:]
    @State private var hasInitialized = false

    private let sortOptions: [ChoiceChip] = [
        ChoiceChip(id: "recommend", title: "推荐"),
        ChoiceChip(id: "new", title: "最新"),
        ChoiceChip(id: "hot", title: "最热")
    ]

    public init(initialTag: String = "全部") { self.initialTag = initialTag }

    private var selectedChoice: ChoiceChip {
        sortOptions.first { $0.id == sortType } ?? sortOptions[0]
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(sortOptions) { option in
                        coolPicPage(sort: option.id)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(option.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledSort)
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .safeAreaBar(edge: .top, spacing: 0) {
                FloatingTabStrip(
                    items: sortOptions,
                    selection: selectedChoice,
                    titleProvider: \.title,
                    onSelect: { option in
                        sortType = option.id
                    },
                    onReselect: { option in
                        withAnimation(.snappy) {
                            proxy.scrollTo("coolpic-top-\(option.id)", anchor: .top)
                        }
                    }
                )
            }
            .navigationTitle("酷图")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scrolledSort) { _, newValue in
                if let newValue, newValue != sortType {
                    sortType = newValue
                }
            }
            .onChange(of: sortType) { _, newValue in
                appState.pageTabSelections["coolpic-\(initialTag)"] = newValue
                if scrolledSort != newValue {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrolledSort = newValue
                    }
                }
                Task { await reload(sort: newValue, force: false) }
            }
            .task(id: initialTag) {
                if let saved = appState.pageTabSelections["coolpic-\(initialTag)"],
                   sortOptions.contains(where: { $0.id == saved }),
                   saved != sortType {
                    sortType = saved
                    scrolledSort = saved
                }
                guard !hasInitialized || loadedSorts.isEmpty else { return }
                hasInitialized = true
                await reload(sort: sortType, force: !loadedSorts.contains(sortType))
            }
        }
    }

    @ViewBuilder
    private func coolPicPage(sort: String) -> some View {
        let rows = rowsBySort[sort] ?? []
        let hasLoaded = loadedSorts.contains(sort)
        let isLoadingSort = loadingSorts.contains(sort)

        if isLoadingSort && rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorBySort[sort], rows.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试") {
                    Task { await reload(sort: sort, force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !hasLoaded && rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView("暂无酷图内容", systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("coolpic-top-\(sort)")
                    LazyVStack(spacing: 10) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= rows.count - 4 { Task { await loadMore(sort: sort) } }
                                }
                        }
                    }
                    .padding(.bottom, 88)
                }
            }
            .refreshable {
                await reload(sort: sort, force: true)
            }
        }
    }

    private func reload(sort: String, force: Bool) async {
        if !force && loadedSorts.contains(sort) { return }
        loadingSorts.insert(sort)
        errorBySort[sort] = nil
        defer {
            loadingSorts.remove(sort)
        }
        pageBySort[sort] = 1
        do {
            if initialTag == "全部" && sort == "recommend" {
                let pageRows = try await API.pageFeed(pageName: "V11_FIND_COOLPIC", page: 1)
                if !pageRows.isEmpty {
                    rowsBySort[sort] = pageRows
                    hasMoreBySort[sort] = true
                    loadedSorts.insert(sort)
                    return
                }
            }
            let fetched = try await API.coolPic(tag: initialTag, type: sort, page: 1)
            rowsBySort[sort] = fetched
            hasMoreBySort[sort] = !fetched.isEmpty
            loadedSorts.insert(sort)
        } catch {
            guard !Task.isCancelled else { return }
            errorBySort[sort] = error.localizedDescription
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(sort: String) async {
        guard hasMoreBySort[sort] != false,
              !loadingSorts.contains(sort),
              !loadingMoreSorts.contains(sort) else { return }
        loadingMoreSorts.insert(sort)
        defer { loadingMoreSorts.remove(sort) }
        let next = (pageBySort[sort] ?? 1) + 1
        let fetched: [HomeFeedRow]?
        if initialTag == "全部" && sort == "recommend" {
            fetched = try? await API.pageFeed(pageName: "V11_FIND_COOLPIC", page: next)
        } else {
            fetched = try? await API.coolPic(tag: initialTag, type: sort, page: next)
        }
        if let fetched {
            let current = rowsBySort[sort] ?? []
            var seen = Set(current.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rowsBySort[sort] = current + unique
            hasMoreBySort[sort] = !unique.isEmpty
            if !unique.isEmpty { pageBySort[sort] = next }
        }
    }
}

public struct InAppWebView: View {
    public let url: URL

    public init(url: URL) { self.url = url }

    public var body: some View {
        WebViewRepresentable(url: url)
            .navigationTitle(url.host ?? "网页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url)
                }
            }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
