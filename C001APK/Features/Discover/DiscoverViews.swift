import CoolapkKit
import SwiftUI
import UIKit
import WebKit

private struct ChoiceChip: Identifiable, Hashable {
    let id: String
    let title: String
}

// MARK: - Topic Detail

public struct TopicDetailView: View {
    public let tag: String

    @Environment(AppState.self) private var appState
    @State private var topic: TopicItem?
    @State private var activeTabID = "lastupdate_desc"
    @State private var scrolledTabID: String? = "lastupdate_desc"
    @State private var sortMode = "lastupdate_desc"
    @State private var rowsByTab: [String: [HomeFeedRow]] = [:]
    @State private var loadedTabs: Set<String> = []
    @State private var loadingTabs: Set<String> = []
    @State private var pageByTab: [String: Int] = [:]
    @State private var hasMoreByTab: [String: Bool] = [:]
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var hasInitialized = false

    private let fallbackTabs: [HomeSection] = [
        HomeSection(id: "lastupdate_desc", title: "最新回复", subtitle: "lastupdate_desc", url: "", style: ""),
        HomeSection(id: "dateline_desc", title: "最新发布", subtitle: "dateline_desc", url: "", style: ""),
        HomeSection(id: "popular", title: "热门", subtitle: "popular", url: "", style: "")
    ]

    public init(tag: String) { self.tag = tag }

    private var activeTabs: [HomeSection] {
        if let apiTabs = topic?.tabs, !apiTabs.isEmpty {
            return apiTabs
        }
        return fallbackTabs
    }

    private var selectedTabItem: HomeSection {
        activeTabs.first { $0.id == activeTabID } ?? activeTabs[0]
    }

    private var isSortMenuAvailable: Bool {
        let tabs = activeTabs
        if tabs == fallbackTabs { return false }
        return selectedTabItem.title == "讨论"
    }

    public var body: some View {
        ScrollViewReader { proxy in
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
            .ignoresSafeArea(.container, edges: .bottom)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaBar(edge: .top, spacing: 0) {
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
            .navigationTitle(topic?.title.isEmpty == false ? "#\(topic!.title)#" : "#\(tag)#")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let topic, compactNavProgress > 0.08 {
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

                if isSortMenuAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("排序方式", selection: $sortMode) {
                                Text("最新回复").tag("lastupdate_desc")
                                Text("最新发布").tag("dateline_desc")
                                Text("热门排序").tag("popular")
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("排序方式")
                    }
                }
            }
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
                if let target = activeTabs.first(where: { $0.id == newValue }) {
                    Task { await reloadFeeds(for: target, force: false) }
                }
            }
            .onChange(of: sortMode) { _, _ in
                Task { await reloadFeeds(for: selectedTabItem, force: true) }
            }
            .task(id: tag) {
                guard !hasInitialized || topic == nil else { return }
                hasInitialized = true
                let loadedTopic = try? await API.topicDetail(tag: tag)
                topic = loadedTopic

                let tabs = activeTabs
                let saved = appState.pageTabSelections["topic-\(tag)"]
                let initialTab: HomeSection? = if let saved, let matchedSaved = tabs.first(where: { $0.id == saved }) {
                    matchedSaved
                } else if let apiSel = loadedTopic?.selectedTab, !apiSel.isEmpty,
                          let matchedAPI = tabs.first(where: { $0.subtitle == apiSel || $0.id == apiSel || $0.title == apiSel }) {
                    matchedAPI
                } else {
                    tabs.first
                }
                if let initialTab {
                    activeTabID = initialTab.id
                    scrolledTabID = initialTab.id
                    await reloadFeeds(for: initialTab, force: !loadedTabs.contains(initialTab.id))
                }
            }
        }
    }

    private func topicFeedScrollPage(for tabItem: HomeSection) -> some View {
        let rows = rowsByTab[tabItem.id] ?? []
        let isLoadingTab = loadingTabs.contains(tabItem.id)
        let hasLoaded = loadedTabs.contains(tabItem.id)

        return ScrollView {
            Color.clear.frame(height: 0).id("topic-top-\(tabItem.id)")
            LazyVStack(alignment: .leading, spacing: 10) {
                if let topic {
                    HStack(spacing: 12) {
                        RemoteImageView(url: topic.logo, maxPixelSize: 180)
                            .frame(width: 56, height: 56)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(topic.title)#").font(.headline)
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
                        Spacer()
                        Button(topic.isFollowed ? "已关注" : "关注") {
                            Task { await toggleFollow(topic) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(topic.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(topic.isFollowed ? Color.primary : Color.accentColor)
                        .disabled(isTogglingFollow)
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 18)
                    .padding(.horizontal, 12)
                    .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                }

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
            .padding(.top, 10)
            .padding(.bottom, 88)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, offset in
            guard tabItem.id == activeTabID else { return }
            let progress = min(1, max(0, (offset - 36) / 70))
            if abs(progress - compactNavProgress) > 0.02 {
                withAnimation(.easeOut(duration: 0.16)) {
                    compactNavProgress = progress
                }
            }
        }
        .refreshable {
            topic = try? await API.topicDetail(tag: tag)
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
            primary = "#\(topic.title)#"
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

    private func effectiveListType(for tabItem: HomeSection) -> String {
        if activeTabs == fallbackTabs {
            return tabItem.id
        }
        return tabItem.title == "讨论" ? sortMode : "lastupdate_desc"
    }

    private func reloadFeeds(for tabItem: HomeSection, force: Bool) async {
        if !force && loadedTabs.contains(tabItem.id) { return }
        loadingTabs.insert(tabItem.id)
        defer {
            loadingTabs.remove(tabItem.id)
            loadedTabs.insert(tabItem.id)
        }
        pageByTab[tabItem.id] = 1
        hasMoreByTab[tabItem.id] = true
        let activeTag = topic?.title.isEmpty == false ? topic!.title : tag
        do {
            let fetched = try await API.topicTabFeeds(
                tag: activeTag,
                topicID: topic?.id,
                tab: tabItem,
                listType: effectiveListType(for: tabItem),
                page: 1
            )
            rowsByTab[tabItem.id] = fetched
            hasMoreByTab[tabItem.id] = !fetched.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(for tabItem: HomeSection) async {
        guard hasMoreByTab[tabItem.id] != false, !loadingTabs.contains(tabItem.id) else { return }
        let next = (pageByTab[tabItem.id] ?? 1) + 1
        let activeTag = topic?.title.isEmpty == false ? topic!.title : tag
        if let fetched = try? await API.topicTabFeeds(
            tag: activeTag,
            topicID: topic?.id,
            tab: tabItem,
            listType: effectiveListType(for: tabItem),
            page: next
        ) {
            let current = rowsByTab[tabItem.id] ?? []
            var seen = Set(current.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
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
        topic?.isFollowed = next
        do {
            try await API.followTopic(tag: targetTag, follow: next)
            appState.showToast(next ? "已关注话题" : "已取消关注")
        } catch {
            topic?.isFollowed = !next
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - Product Detail

public struct ProductDetailView: View {
    public let productID: String

    @Environment(AppState.self) private var appState
    @State private var product: ProductItem?
    @State private var apiTabs: [HomeSection] = []
    @State private var activeTabID = "lastupdate_desc"
    @State private var scrolledTabID: String? = "lastupdate_desc"
    @State private var rowsByTab: [String: [HomeFeedRow]] = [:]
    @State private var loadedTabs: Set<String> = []
    @State private var loadingTabs: Set<String> = []
    @State private var pageByTab: [String: Int] = [:]
    @State private var hasMoreByTab: [String: Bool] = [:]
    @State private var isLoadingHeader = true
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var hasInitialized = false
    @State private var productVariants: [ProductConfigVariant] = []
    @State private var productSpecs: [ProductSpecEntry] = []
    @State private var variantSpecSectionsByID: [String: [ProductSpecSection]] = [:]
    @State private var loadingVariantSpecIDs: Set<String> = []
    @State private var selectedVariantID: String = ""
    @State private var isLoadingSpecs = false

    private let fallbackTabs: [ChoiceChip] = [
        ChoiceChip(id: "lastupdate_desc", title: "最新回复"),
        ChoiceChip(id: "dateline_desc", title: "最新发布"),
        ChoiceChip(id: "popular", title: "热门讨论")
    ]

    public init(productID: String) { self.productID = productID }

    private func isConfigTab(id: String, title: String) -> Bool {
        let lowerID = id.lowercased()
        return id == "__specs__"
            || title.contains("参数")
            || title.contains("配置")
            || lowerID.contains("config")
            || lowerID.contains("param")
    }

    private var activeChips: [ChoiceChip] {
        var base: [ChoiceChip] = !apiTabs.isEmpty
            ? apiTabs.map { ChoiceChip(id: $0.url, title: $0.title) }
            : fallbackTabs
        if !base.contains(where: { isConfigTab(id: $0.id, title: $0.title) }) {
            base.append(ChoiceChip(id: "__specs__", title: "参数"))
        }
        return base
    }

    private var selectedChip: ChoiceChip {
        activeChips.first { $0.id == activeTabID } ?? activeChips[0]
    }

    public var body: some View {
        ScrollViewReader { proxy in
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
            .ignoresSafeArea(.container, edges: .bottom)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaBar(edge: .top, spacing: 0) {
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
            .navigationTitle(product?.title ?? "数码产品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let product, compactNavProgress > 0.08 {
                    let line1 = [
                        product.score.isEmpty ? nil : "评分 \(product.score)",
                        product.priceText.isEmpty ? nil : product.priceText
                    ].compactMap { $0 }.joined(separator: " · ")
                    let line2 = "\(Formatting.count(product.followNum)) 关注"
                        + (product.feedNum > 0 ? " · \(Formatting.count(product.feedNum)) 讨论" : "")
                    CollapsedNavEntityToolbar(
                        avatarURL: product.logo,
                        primaryLine: line1.isEmpty ? "数码产品" : line1,
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
            }
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
                Task { await reloadFeeds(for: newValue, force: false) }
            }
            .task(id: productID) {
                if let saved = appState.pageTabSelections["product-\(productID)"], !saved.isEmpty {
                    activeTabID = saved
                    scrolledTabID = saved
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

        return ScrollView {
            Color.clear.frame(height: 0).id("product-top-\(chip.id)")
            LazyVStack(alignment: .leading, spacing: 10) {
                if let product {
                    productHeaderCard(product)
                        .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                } else if isLoadingHeader {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                }

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
            .padding(.top, 10)
            .padding(.bottom, 88)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, offset in
            guard chip.id == activeTabID else { return }
            let progress = min(1, max(0, (offset - 36) / 70))
            if abs(progress - compactNavProgress) > 0.02 {
                withAnimation(.easeOut(duration: 0.16)) {
                    compactNavProgress = progress
                }
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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Spacer()
                Button(product.isFollowed ? "已关注" : "关注") {
                    Task { await toggleFollow(product) }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(product.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
                .foregroundStyle(product.isFollowed ? Color.primary : Color.accentColor)
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
        .padding(14)
        .c001CardStyle(cornerRadius: 18)
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
                    .c001CardStyle(cornerRadius: 18)
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
                        .c001CardStyle(cornerRadius: 18)
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
                    .c001CardStyle(cornerRadius: 18)
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
        let detail = try? await API.productDetail(id: productID)
        product = detail
        isLoadingHeader = false
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
                let saved = appState.pageTabSelections["product-\(productID)"]
                if let saved, activeChips.contains(where: { $0.id == saved }) {
                    activeTabID = saved
                    scrolledTabID = saved
                } else if !activeChips.contains(where: { $0.id == activeTabID }),
                          let first = activeChips.first?.id {
                    activeTabID = first
                    scrolledTabID = first
                }
            }
        }
        await reloadFeeds(for: activeTabID, force: true)
    }

    private func reloadFeeds(for tabID: String, force: Bool) async {
        if !force && loadedTabs.contains(tabID) { return }
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
            loadedTabs.insert(tabID)
        }
        pageByTab[tabID] = 1
        hasMoreByTab[tabID] = true
        let tabURL: String? = apiTabs.isEmpty ? nil : tabID
        let sort = apiTabs.isEmpty ? tabID : "lastupdate_desc"
        do {
            let fetched = try await API.productFeeds(
                productID: productID,
                title: product?.title ?? "",
                tabURL: tabURL,
                listType: sort,
                page: 1
            )
            rowsByTab[tabID] = fetched
            hasMoreByTab[tabID] = !fetched.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(for tabID: String) async {
        let chipTitle = activeChips.first(where: { $0.id == tabID })?.title ?? ""
        guard !isConfigTab(id: tabID, title: chipTitle) else { return }
        guard hasMoreByTab[tabID] != false, !loadingTabs.contains(tabID) else { return }
        let next = (pageByTab[tabID] ?? 1) + 1
        let tabURL: String? = apiTabs.isEmpty ? nil : tabID
        let sort = apiTabs.isEmpty ? tabID : "lastupdate_desc"
        if let fetched = try? await API.productFeeds(
            productID: productID,
            title: product?.title ?? "",
            tabURL: tabURL,
            listType: sort,
            page: next
        ) {
            let current = rowsByTab[tabID] ?? []
            var seen = Set(current.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
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
        product?.isFollowed = next
        do {
            try await API.followProduct(id: current.id, follow: next)
            appState.showToast(next ? "已关注机型" : "已取消关注")
        } catch {
            product?.isFollowed = !next
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - App Detail

public struct AppDetailView: View {
    public let appID: String

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var app: AppItem?
    @State private var comments: [HomeFeedRow] = []
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var page = 1
    @State private var hasMore = true

    public init(appID: String) { self.appID = appID }

    public var body: some View {
        ScrollView {
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
                                Text("\(app.version) · \(app.size) · \(app.developer)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !app.score.isEmpty {
                                    Label("\(app.score) 分", systemImage: "star.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
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
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .applyZoomSource(id: "\(shotPrefix)-\(idx)", in: zoomNamespace)
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
                    .c001CardStyle(cornerRadius: 18)
                    .padding(.horizontal, 12)
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
        .refreshable {
            await reload()
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(app?.title ?? "应用详情")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appID) {
            await reload()
        }
    }

    private func reload() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        page = 1
        async let detailTask = try? API.appDetail(id: appID)
        async let commentsTask = (try? API.appComments(id: appID, page: 1)) ?? []
        app = await detailTask
        comments = await commentsTask
        hasMore = !comments.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let next = page + 1
        if let fetched = try? await API.appComments(id: appID, page: next) {
            var seen = Set(comments.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            comments.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }
}

// MARK: - Dyh (看看号)

public struct DyhDetailView: View {
    public let dyhID: String

    @Environment(AppState.self) private var appState
    @State private var dyh: DyhItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var page = 1
    @State private var hasMore = true

    public init(dyhID: String) { self.dyhID = dyhID }

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
                            .background(dyh.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .foregroundStyle(dyh.isFollowed ? Color.primary : Color.accentColor)
                            .disabled(isTogglingFollow)
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 18)
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(dyh?.title ?? "看看号")
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
            .task(id: dyhID) {
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
        dyh = await detailTask
        rows = await rowsTask
        hasMore = !rows.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
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
        dyh?.isFollowed = next
        do {
            try await API.followDyh(id: dyhID, follow: next)
            appState.showToast(next ? "已订阅" : "已取消订阅")
        } catch {
            dyh?.isFollowed = !next
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - Collection (收藏夹)

public struct CollectionDetailView: View {
    public let collectionID: String

    @Environment(AppState.self) private var appState
    @State private var collection: CollectionItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var isTogglingFollow = false
    @State private var compactNavProgress: CGFloat = 0
    @State private var page = 1
    @State private var hasMore = true

    public init(collectionID: String) { self.collectionID = collectionID }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("col-top")
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let collection {
                        HStack(spacing: 12) {
                            RemoteImageView(url: collection.logo, maxPixelSize: 180)
                                .frame(width: 56, height: 56)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(collection.title).font(.headline)
                                Text("\(collection.itemNum) 项 · \(Formatting.count(collection.followNum)) 关注")
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
                            .background(collection.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .foregroundStyle(collection.isFollowed ? Color.primary : Color.accentColor)
                            .disabled(isTogglingFollow)
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 18)
                        .padding(.horizontal, 12)
                        .opacity(max(0.25, 1.0 - compactNavProgress * 0.65))
                    }

                    if (!hasLoaded || isLoading) && rows.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else if rows.isEmpty {
                        ContentUnavailableView("暂无收藏内容", systemImage: "star")
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(collection?.title ?? "收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let collection, compactNavProgress > 0.08 {
                    CollapsedNavEntityToolbar(
                        avatarURL: collection.logo,
                        primaryLine: "\(collection.itemNum) 项内容",
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
            .task(id: collectionID) {
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
        async let detailTask = try? API.collectionDetail(id: collectionID)
        async let itemsTask = (try? API.collectionItems(id: collectionID, page: 1)) ?? []
        collection = await detailTask
        rows = await itemsTask
        hasMore = !rows.isEmpty
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
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
        collection?.isFollowed = next
        do {
            try await API.followCollection(id: collectionID, follow: next)
            appState.showToast(next ? "已关注收藏夹" : "已取消关注")
        } catch {
            collection?.isFollowed = !next
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - Event Detail

public struct EventDetailView: View {
    public let eventID: String
    public let initialEvent: EventItem?

    @Environment(AppState.self) private var appState
    @State private var event: EventItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var hasLoaded = false
    @State private var isLoading = true
    @State private var page = 1
    @State private var hasMore = true

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
                            Color.clear
                                .frame(height: 196)
                                .overlay {
                                    RemoteImageView(url: event.cover, maxPixelSize: 1200)
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
        guard hasMore, !isLoading else { return }
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
    @State private var rowsByTab: [String: [HomeFeedRow]] = [:]
    @State private var loadedTabs: Set<String> = []
    @State private var loadingTabs: Set<String> = []
    @State private var pageByTab: [String: Int] = [:]
    @State private var hasMoreByTab: [String: Bool] = [:]
    @State private var hasInitialized = false

    public init(link: String, title: String) {
        self.link = link
        self.title = title
    }

    private var activeTab: HomeSection {
        subTabs.first { $0.id == selectedTabID }
            ?? subTabs.first
            ?? HomeSection(id: link, title: title, subtitle: "", url: link, style: "")
    }

    public var body: some View {
        Group {
            if subTabs.isEmpty {
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
                        }
                    )
                }
            }
        }
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
            if let tab = subTabs.first(where: { $0.id == newID }) {
                Task { await loadSubTab(tabID: tab.id, url: tab.url, force: false) }
            }
        }
        .task(id: link) {
            if let saved = appState.pageTabSelections["page-\(link)"], !saved.isEmpty {
                if selectedTabID.isEmpty {
                    selectedTabID = saved
                }
                if !subTabs.isEmpty && subTabs.contains(where: { $0.id == saved }) {
                    scrolledTabID = saved
                }
            }
            guard !hasInitialized || (subTabs.isEmpty && (rowsByTab[link]?.isEmpty ?? true)) else { return }
            hasInitialized = true
            await loadInitial()
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
                LazyVStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        HomeRowRenderer(row: row)
                            .onAppear {
                                if idx >= rows.count - 4 { Task { await loadMore(tabID: tabID, url: tabURL) } }
                            }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 88)
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

    private func loadInitial() async {
        loadingTabs.insert(link)
        defer {
            loadingTabs.remove(link)
            loadedTabs.insert(link)
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
            let extractedTabs = extractSubTabs(from: initial)
            if !extractedTabs.isEmpty {
                let contentOnly = filterNonTabRows(initial)
                var resolvedTabs = extractedTabs
                let preferredSavedID = appState.pageTabSelections["page-\(link)"]
                if !contentOnly.isEmpty {
                    let existingIdx = resolvedTabs.firstIndex { tab in
                        normalizedComparisonKey(tab.url) == normalizedComparisonKey(link)
                    }
                    if let existingIdx {
                        let firstTab = resolvedTabs[existingIdx]
                        subTabs = resolvedTabs
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
                        await loadSubTab(tabID: targetTab.id, url: targetTab.url, force: false)
                    }
                }
            } else {
                subTabs = []
                selectedTabID = link
                rowsByTab[link] = initial
                pageByTab[link] = 1
                hasMoreByTab[link] = !initial.isEmpty
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadSubTab(tabID: String, url: String, force: Bool) async {
        if !force && loadedTabs.contains(tabID) { return }
        loadingTabs.insert(tabID)
        defer {
            loadingTabs.remove(tabID)
            loadedTabs.insert(tabID)
        }
        pageByTab[tabID] = 1
        do {
            let fetched: [HomeFeedRow]
            if url == "/main/headline" {
                fetched = try await API.headlineFeed(page: 1)
            } else {
                fetched = try await API.linkFeed(link: url, page: 1)
            }
            let filtered = filterNonTabRows(fetched)
            rowsByTab[tabID] = filtered
            hasMoreByTab[tabID] = !filtered.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore(tabID: String, url: String) async {
        guard hasMoreByTab[tabID] != false, !loadingTabs.contains(tabID) else { return }
        let next = (pageByTab[tabID] ?? 1) + 1
        let fetched: [HomeFeedRow]?
        if url == "/main/headline" {
            fetched = try? await API.headlineFeed(page: next)
        } else {
            fetched = try? await API.linkFeed(link: url, page: next)
        }
        if let fetched {
            let filtered = subTabs.isEmpty ? fetched : filterNonTabRows(fetched)
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
            case let .linkBar(_, sections), let .columnTabs(_, sections):
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

        if (!hasLoaded || isLoadingSort) && rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView("暂无酷图内容", systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Color.clear.frame(height: 0).id("coolpic-top-\(sort)")
                LazyVStack(spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        HomeRowRenderer(row: row)
                            .onAppear {
                                if idx >= rows.count - 4 { Task { await loadMore(sort: sort) } }
                            }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 88)
            }
            .refreshable {
                await reload(sort: sort, force: true)
            }
        }
    }

    private func reload(sort: String, force: Bool) async {
        if !force && loadedSorts.contains(sort) { return }
        loadingSorts.insert(sort)
        defer {
            loadingSorts.remove(sort)
            loadedSorts.insert(sort)
        }
        pageBySort[sort] = 1
        if initialTag == "全部" && sort == "recommend" {
            let pageRows = (try? await API.pageFeed(pageName: "V11_FIND_COOLPIC", page: 1)) ?? []
            if !pageRows.isEmpty {
                rowsBySort[sort] = pageRows
                hasMoreBySort[sort] = true
                return
            }
        }
        let fetched = (try? await API.coolPic(tag: initialTag, type: sort, page: 1)) ?? []
        rowsBySort[sort] = fetched
        hasMoreBySort[sort] = !fetched.isEmpty
    }

    private func loadMore(sort: String) async {
        guard hasMoreBySort[sort] != false, !loadingSorts.contains(sort) else { return }
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
