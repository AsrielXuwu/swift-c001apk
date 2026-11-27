import CoolapkKit
import SwiftUI

public struct FollowView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = FollowViewModel()
    @State private var scrolledSegment: FollowSegment? = .all

    public init() {}

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(FollowSegment.allCases) { seg in
                        segmentContent(for: seg)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                            .id(seg)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledSegment)
            .scrollClipDisabled()
            .ignoresSafeArea(.container, edges: .bottom)
            .c001PageBackground()
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    floatingSegmentStrip
                    if viewModel.segment == .topics && !viewModel.followedTopics.isEmpty {
                        topicChipsStrip
                    }
                }
            }
            .navigationTitle("关注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.push(.localFollowList)
                    } label: {
                        Label("本机关注名单", systemImage: "person.badge.shield.checkmark")
                    }
                }
            }
            .onChange(of: scrolledSegment) { _, newSeg in
                if let newSeg, newSeg != viewModel.segment {
                    viewModel.segment = newSeg
                }
            }
            .onChange(of: viewModel.segment) { _, newSeg in
                if scrolledSegment != newSeg {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrolledSegment = newSeg
                    }
                }
            }
            .task(id: "\(appState.isSessionBootstrapped)|\(appState.sessionVersion)|\(appState.settings.enableCloudFollowLoad)|\(viewModel.segment.rawValue)") {
                guard appState.isSessionBootstrapped else { return }
                await viewModel.loadInitial(segment: viewModel.segment, appState: appState)
            }
            .onChange(of: appState.followDoubleTapTrigger) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo("follow-top-\(viewModel.segment.rawValue)", anchor: .top)
                }
                Task {
                    await viewModel.loadInitial(segment: viewModel.segment, appState: appState, force: true)
                }
            }
        }
    }

    private var floatingSegmentStrip: some View {
        FloatingTabStrip(
            items: FollowSegment.allCases,
            selection: viewModel.segment,
            titleProvider: { $0.rawValue },
            onSelect: { seg in
                viewModel.segment = seg
            }
        )
    }

    private struct FollowTopicChip: Identifiable, Hashable {
        let id: String
        let title: String
    }

    private var topicChipsStrip: some View {
        let items = viewModel.followedTopics.map {
            FollowTopicChip(id: $0.title, title: TopicItem.cleanTitle($0.title))
        }
        let selected = items.first { $0.id == viewModel.selectedTopicTag }
        return FloatingTabStrip(
            items: items,
            selection: selected,
            titleProvider: \.title,
            onSelect: { chip in
                viewModel.selectedTopicTag = chip.id
                Task { await viewModel.loadInitial(segment: .topics, appState: appState, force: true) }
            },
            onReselect: { chip in
                viewModel.selectedTopicTag = chip.id
                Task { await viewModel.loadInitial(segment: .topics, appState: appState, force: true) }
            }
        )
    }

    @ViewBuilder
    private func segmentContent(for seg: FollowSegment) -> some View {
        let segRows = viewModel.rowsBySegment[seg] ?? []
        let segLoading = viewModel.loadingSegments.contains(seg)
        let segHasLoaded = viewModel.loadedSegments.contains(seg)
        let segLoadingMore = viewModel.loadingMoreSegments.contains(seg)
        let segError = viewModel.errorBySegment[seg]

        if !appState.accounts.isLoggedIn && seg == .topics {
            ContentUnavailableView {
                Label("需要登录酷安账号", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("游客模式可切换到“全部”“关注用户”或“本机关注”浏览本地关注动态。")
            } actions: {
                Button("立即登录") { appState.showLoginSheet = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if segLoading && segRows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let segError, segRows.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(segError)
            } actions: {
                Button("重试") { Task { await viewModel.loadInitial(segment: seg, appState: appState, force: true) } }
                    .buttonStyle(.borderedProminent)
            }
        } else if !segHasLoaded && segRows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if segRows.isEmpty {
            ContentUnavailableView {
                Label("暂无\(seg.rawValue)动态", systemImage: "person.2")
            } description: {
                Text(emptyDescription(for: seg))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("follow-top-\(seg.rawValue)")
                    LazyVStack(spacing: 10) {
                        ForEach(Array(segRows.enumerated()), id: \.element.id) { index, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if index >= segRows.count - 4 {
                                        Task { await viewModel.loadMore(segment: seg, appState: appState) }
                                    }
                                }
                        }

                        if segLoadingMore {
                            ProgressView()
                                .padding(.vertical, 16)
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 88)
                }
            }
            .refreshable {
                await viewModel.loadInitial(segment: seg, appState: appState, force: true)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private func emptyDescription(for seg: FollowSegment) -> String {
        switch seg {
        case .local:
            return "可在用户主页点击或长按关注按钮添加到本机关注。"
        case .users:
            return appState.accounts.isLoggedIn ? "暂未关注任何酷友，或所关注用户暂无最新动态。" : "登录后可查看关注的酷友动态。"
        case .topics:
            return "暂未关注任何话题，关注感兴趣的话题即可在这里查看。"
        case .all:
            return "关注更多酷友或话题即可在这里查看最新动态。"
        }
    }
}
