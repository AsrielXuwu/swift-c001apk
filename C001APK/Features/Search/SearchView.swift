import CoolapkKit
import SwiftUI

public struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SearchViewModel()
    @State private var scrolledCategory: SearchCategory? = .all

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        Group {
            if state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.submittedKeyword.isEmpty {
                discoveryLanding
            } else if viewModel.submittedKeyword.isEmpty || viewModel.submittedKeyword != state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) && !viewModel.suggestions.isEmpty {
                suggestionsList
            } else {
                resultsView
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("搜索范围", selection: $viewModel.category) {
                        ForEach(SearchCategory.allCases) { cat in
                            Text(cat.label).tag(cat)
                        }
                    }

                    if viewModel.category == .all {
                        Picker("动态类型", selection: $viewModel.feedFilter) {
                            ForEach(SearchFeedFilter.allCases) { filter in
                                Text(filter.label).tag(filter)
                            }
                        }

                        Picker("排序方式", selection: $viewModel.sortOrder) {
                            ForEach(SearchSortOrder.allCases) { sort in
                                Text(sort.label).tag(sort)
                            }
                        }
                    }
                } label: {
                    Image(systemName: viewModel.feedFilter == .all && viewModel.category == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("搜索类型与排序")
            }
        }
        .searchable(text: $state.searchQuery, prompt: searchPrompt)
        .onSubmit(of: .search) {
            Task { await viewModel.submitSearch(appState.searchQuery, category: viewModel.category, appState: appState, force: true) }
        }
        .onChange(of: appState.searchQuery) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.submittedKeyword = ""
            }
            viewModel.updateSuggestions(for: newValue)
        }
        .onChange(of: viewModel.feedFilter) { _, _ in
            if viewModel.category == .all && !viewModel.submittedKeyword.isEmpty {
                Task { await viewModel.submitSearch(viewModel.submittedKeyword, category: .all, appState: appState, force: true) }
            }
        }
        .onChange(of: viewModel.sortOrder) { _, _ in
            if viewModel.category == .all && !viewModel.submittedKeyword.isEmpty {
                Task { await viewModel.submitSearch(viewModel.submittedKeyword, category: .all, appState: appState, force: true) }
            }
        }
        .task(id: appState.isSessionBootstrapped) {
            guard appState.isSessionBootstrapped else { return }
            await viewModel.loadDiscoveryIfNeeded()
        }
    }

    private var searchPrompt: String {
        if viewModel.category == .all {
            if viewModel.feedFilter != .all {
                return "在「\(viewModel.feedFilter.label)」中搜索"
            }
            return "搜索动态、话题、用户、应用"
        }
        return "搜索\(viewModel.category.label)"
    }

    private var discoveryLanding: some View {
        List {
            Section("按类型搜索（可先指定范围）") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SearchCategory.allCases) { cat in
                            let selected = viewModel.category == cat
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    viewModel.category = cat
                                }
                            } label: {
                                Text(cat.label)
                                    .font(.subheadline.weight(selected ? .semibold : .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemFill), in: Capsule())
                                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if viewModel.category == .all {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SearchFeedFilter.allCases) { filter in
                                let selected = viewModel.feedFilter == filter
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        viewModel.feedFilter = filter
                                    }
                                } label: {
                                    Text(filter.label)
                                        .font(.caption.weight(selected ? .semibold : .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(selected ? Color.orange.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                                        .foregroundStyle(selected ? Color.orange : Color.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }

            if !appState.settings.searchHistory.isEmpty {
                Section {
                    ForEach(appState.settings.searchHistory, id: \.self) { term in
                        Button {
                            appState.searchQuery = term
                            Task { await viewModel.submitSearch(term, category: viewModel.category, appState: appState, force: true) }
                        } label: {
                            Label(term, systemImage: "clock")
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                appState.settings.removeSearchHistory(term)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("搜索历史")
                        Spacer()
                        Button("清空") {
                            appState.settings.clearSearchHistory()
                        }
                        .font(.caption)
                    }
                }
            }

            if !viewModel.hotWords.isEmpty {
                Section("热门搜索") {
                    ForEach(Array(viewModel.hotWords.enumerated()), id: \.offset) { idx, word in
                        Button {
                            appState.searchQuery = word
                            Task { await viewModel.submitSearch(word, category: viewModel.category, appState: appState, force: true) }
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(idx + 1)")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(idx < 3 ? Color.orange : Color.secondary)
                                    .frame(width: 20)
                                Text(word)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "magnifyingglass")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Section {
                if viewModel.isLoadingDiscovery && viewModel.hotRankingRows.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.hotRankingRows.isEmpty {
                    Text("下拉或稍后刷新加载热榜")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.hotRankingRows.prefix(20).enumerated()), id: \.element.id) { idx, row in
                        hotRankingRowView(row: row, rank: idx + 1)
                    }
                }
            } header: {
                HStack {
                    Text("酷安热榜")
                    Spacer()
                    Button("完整热榜") {
                        appState.push(.page(link: "V9_HOME_TAB_RANKING", title: "热榜"))
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadDiscoveryIfNeeded(force: true)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private func hotRankingRowView(row: HomeFeedRow, rank: Int) -> some View {
        switch row {
        case let .feed(feed):
            let headline = !feed.messageTitle.isEmpty
                ? feed.messageTitle
                : FeedHTMLParser.plainText(feed.message).trimmingCharacters(in: .whitespacesAndNewlines)
            Button {
                appState.push(.feed(id: feed.effectiveFeedID, initial: feed))
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(rank)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(rank <= 3 ? Color.red : Color.secondary)
                        .frame(width: 22, alignment: .center)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline.isEmpty ? feed.username : headline)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if !feed.username.isEmpty {
                                Text(feed.username)
                            }
                            if feed.replyNum > 0 {
                                Text("\(Formatting.count(feed.replyNum)) 评")
                            }
                            if feed.likeNum > 0 {
                                Text("\(Formatting.count(feed.likeNum)) 赞")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
            }
        case let .topic(topic):
            Button {
                appState.push(.topic(tag: topic.title))
            } label: {
                HStack(spacing: 10) {
                    Text("\(rank)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(rank <= 3 ? Color.red : Color.secondary)
                        .frame(width: 22)
                    Text("#\(topic.title)#")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(
                        topic.feedNum > 0
                            ? "\(Formatting.count(topic.feedNum)) 讨论"
                            : (!topic.feedNumText.isEmpty
                                ? "\(topic.feedNumText) 讨论"
                                : (!topic.hotNumText.isEmpty ? "\(topic.hotNumText) 热度" : "0 讨论"))
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case let .product(product):
            Button {
                appState.push(.product(id: product.id))
            } label: {
                HStack(spacing: 10) {
                    Text("\(rank)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(rank <= 3 ? Color.red : Color.secondary)
                        .frame(width: 22)
                    Text(product.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        default:
            EmptyView()
        }
    }

    private var suggestionsList: some View {
        List(viewModel.suggestions, id: \.self) { word in
            Button {
                appState.searchQuery = word
                Task { await viewModel.submitSearch(word, category: viewModel.category, appState: appState, force: true) }
            } label: {
                Label(word, systemImage: "magnifyingglass")
            }
        }
        .listStyle(.plain)
    }

    private var resultsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(SearchCategory.allCases) { cat in
                    categoryResultPage(for: cat)
                        .containerRelativeFrame(.horizontal)
                        .frame(maxHeight: .infinity)
                        .id(cat)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledCategory)
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaBar(edge: .top, spacing: 0) {
            FloatingTabStrip(
                items: SearchCategory.allCases,
                selection: viewModel.category,
                titleProvider: { $0.label },
                onSelect: { cat in
                    viewModel.category = cat
                }
            )
        }
        .onChange(of: scrolledCategory) { _, newCat in
            if let newCat, newCat != viewModel.category {
                viewModel.category = newCat
            }
        }
        .onChange(of: viewModel.category) { _, newCat in
            if scrolledCategory != newCat {
                withAnimation(.snappy(duration: 0.24)) {
                    scrolledCategory = newCat
                }
            }
            if !viewModel.submittedKeyword.isEmpty {
                Task { await viewModel.submitSearch(viewModel.submittedKeyword, category: newCat, appState: appState) }
            }
        }
    }

    @ViewBuilder
    private func categoryResultPage(for cat: SearchCategory) -> some View {
        let isSearching = viewModel.searchingCategories.contains(cat)
        let expectedKey = viewModel.currentQueryKey(for: viewModel.submittedKeyword, category: cat)
        let hasLoaded = viewModel.searchedQueryKeyByCategory[cat] == expectedKey && !viewModel.submittedKeyword.isEmpty
        let rows = viewModel.rowsByCategory[cat] ?? []
        let isEmpty = cat == .dyh ? viewModel.dyhResults.isEmpty : rows.isEmpty

        if (!hasLoaded || isSearching) && isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            ContentUnavailableView.search(text: viewModel.submittedKeyword)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if cat == .dyh {
                        ForEach(Array(viewModel.dyhResults.enumerated()), id: \.element.id) { idx, dyh in
                            Button {
                                appState.push(.dyh(id: dyh.id))
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImageView(url: dyh.logo, maxPixelSize: 132)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(dyh.title).font(.body.weight(.medium))
                                        Text(dyh.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .c001CardStyle(cornerRadius: 16)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if idx >= viewModel.dyhResults.count - 4 {
                                    Task { await viewModel.loadMore(category: .dyh, appState: appState) }
                                }
                            }
                        }
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= rows.count - 4 {
                                        Task { await viewModel.loadMore(category: cat, appState: appState) }
                                    }
                                }
                        }
                    }
                    if viewModel.loadingMoreCategories.contains(cat) {
                        ProgressView().padding(.vertical, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 88)
            }
            .refreshable {
                await viewModel.submitSearch(viewModel.submittedKeyword, category: cat, appState: appState, force: true)
            }
        }
    }
}
