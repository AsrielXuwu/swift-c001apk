import CoolapkKit
import SwiftUI

public struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = SearchViewModel()

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
            Task { await viewModel.submitSearch(appState.searchQuery, appState: appState) }
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
                            Task { await viewModel.submitSearch(term, appState: appState) }
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
                            Task { await viewModel.submitSearch(word, appState: appState) }
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
                Task { await viewModel.submitSearch(word, appState: appState) }
            } label: {
                Label(word, systemImage: "magnifyingglass")
            }
        }
        .listStyle(.plain)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching && viewModel.rows.isEmpty && viewModel.dyhResults.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.rows.isEmpty && viewModel.dyhResults.isEmpty {
                ContentUnavailableView.search(text: viewModel.submittedKeyword)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if viewModel.category == .dyh {
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
                                        Task { await viewModel.loadMore(appState: appState) }
                                    }
                                }
                            }
                        } else {
                            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { idx, row in
                                HomeRowRenderer(row: row)
                                    .onAppear {
                                        if idx >= viewModel.rows.count - 4 {
                                            Task { await viewModel.loadMore(appState: appState) }
                                        }
                                    }
                            }
                        }
                        if viewModel.isLoadingMore {
                            ProgressView().padding(.vertical, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .contentMargins(.top, 52, for: .scrollContent)
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(SearchCategory.allCases) { cat in
                        let isSelected = viewModel.category == cat
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.category = cat
                            }
                        } label: {
                            Text(cat.label)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .onChange(of: viewModel.category) { _, _ in
                Task { await viewModel.submitSearch(appState.searchQuery, appState: appState) }
            }
        }
    }
}
