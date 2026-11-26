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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 6) {
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
            .task(id: "\(appState.sessionVersion)|\(viewModel.segment.rawValue)") {
                await viewModel.loadInitial(appState: appState, force: true)
            }
            .onChange(of: appState.followDoubleTapTrigger) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("follow-top-\(viewModel.segment.rawValue)", anchor: .top) }
            }
        }
    }

    private var floatingSegmentStrip: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(FollowSegment.allCases) { seg in
                    let isSelected = viewModel.segment == seg
                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            viewModel.segment = seg
                        }
                    } label: {
                        Text(seg.rawValue)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: Capsule()
                            )
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
        .padding(.bottom, viewModel.segment == .topics && !viewModel.followedTopics.isEmpty ? 0 : 6)
    }

    private var topicChipsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(viewModel.followedTopics) { topic in
                        let selected = viewModel.selectedTopicTag == topic.title
                        Button {
                            viewModel.selectedTopicTag = topic.title
                            Task { await viewModel.loadInitial(appState: appState, force: true) }
                        } label: {
                            Text("#\(topic.title)")
                                .font(.caption.weight(selected ? .semibold : .medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(
                                    selected ? Color.accentColor.opacity(0.18) : Color.clear,
                                    in: Capsule()
                                )
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func segmentContent(for seg: FollowSegment) -> some View {
        if !appState.accounts.isLoggedIn && (seg == .users || seg == .topics) {
            ContentUnavailableView {
                Label("需要登录酷安账号", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("游客模式可切换到“全部”或“本机关注”浏览已保存的本地关注动态。")
            } actions: {
                Button("立即登录") { appState.showLoginSheet = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if viewModel.segment != seg {
            Color.clear
        } else if viewModel.isLoading && viewModel.rows.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试") { Task { await viewModel.loadInitial(appState: appState, force: true) } }
                    .buttonStyle(.borderedProminent)
            }
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label("暂无关注动态", systemImage: "person.2")
            } description: {
                Text(seg == .local || !appState.accounts.isLoggedIn
                     ? "可在用户主页点击或长按关注按钮添加到本机关注。"
                     : "关注更多酷友或话题即可在这里查看最新动态。")
            }
        } else {
            ScrollView {
                Color.clear.frame(height: 0).id("follow-top-\(seg.rawValue)")
                LazyVStack(spacing: 10) {
                    ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                        HomeRowRenderer(row: row)
                            .onAppear {
                                if index >= viewModel.rows.count - 4 {
                                    Task { await viewModel.loadMore(appState: appState) }
                                }
                            }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding(.vertical, 16)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 88)
            }
            .refreshable {
                await viewModel.loadInitial(appState: appState, force: true)
            }
        }
    }
}
