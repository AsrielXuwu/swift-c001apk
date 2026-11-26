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
        .searchable(text: $state.searchQuery, prompt: "搜索动态、话题、用户、应用")
        .onSubmit(of: .search) {
            Task { await viewModel.submitSearch(appState.searchQuery, category: viewModel.category, appState: appState, force: true) }
        }
        .onChange(of: appState.searchQuery) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.submittedKeyword = ""
            }
            viewModel.updateSuggestions(for: newValue)
        }
        .task {
            await viewModel.loadHotWordsIfNeeded()
        }
    }

    private var discoveryLanding: some View {
        List {
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
                Section("酷安热搜") {
                    ForEach(viewModel.hotWords, id: \.self) { word in
                        Button {
                            appState.searchQuery = word
                            Task { await viewModel.submitSearch(word, category: viewModel.category, appState: appState, force: true) }
                        } label: {
                            Label(word, systemImage: "flame")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
        .safeAreaInset(edge: .top, spacing: 0) {
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
        let hasLoaded = viewModel.searchedKeywordByCategory[cat] == viewModel.submittedKeyword && !viewModel.submittedKeyword.isEmpty
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
