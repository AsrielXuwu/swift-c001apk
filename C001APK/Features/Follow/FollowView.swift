import CoolapkKit
import SwiftUI

public struct FollowView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = FollowViewModel()

    public init() {}

    public var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Picker("来源", selection: $viewModel.segment) {
                    ForEach(FollowSegment.allCases) { seg in
                        Text(seg.rawValue).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if viewModel.segment == .topics && !viewModel.followedTopics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.followedTopics) { topic in
                                let selected = viewModel.selectedTopicTag == topic.title
                                Button {
                                    viewModel.selectedTopicTag = topic.title
                                    Task { await viewModel.loadInitial(appState: appState, force: true) }
                                } label: {
                                    Text("#\(topic.title)")
                                        .font(.caption.weight(selected ? .semibold : .regular))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            selected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selected ? Color.accentColor : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }

                contentList
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
            .task(id: "\(appState.sessionVersion)|\(viewModel.segment.rawValue)") {
                await viewModel.loadInitial(appState: appState, force: true)
            }
            .onChange(of: appState.followDoubleTapTrigger) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("follow-top", anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        if !appState.accounts.isLoggedIn && (viewModel.segment == .users || viewModel.segment == .topics) {
            ContentUnavailableView {
                Label("需要登录酷安账号", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("游客模式可切换到“全部”或“本机关注”浏览已保存的本地关注动态。")
            } actions: {
                Button("立即登录") { appState.showLoginSheet = true }
                    .buttonStyle(.borderedProminent)
            }
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
                Text(viewModel.segment == .local || !appState.accounts.isLoggedIn
                     ? "可在用户主页点击或长按关注按钮添加到本机关注。"
                     : "关注更多酷友或话题即可在这里查看最新动态。")
            }
        } else {
            ScrollView {
                Color.clear.frame(height: 0).id("follow-top")
                LazyVStack(spacing: 0) {
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
            }
            .refreshable {
                await viewModel.loadInitial(appState: appState, force: true)
            }
        }
    }
}
