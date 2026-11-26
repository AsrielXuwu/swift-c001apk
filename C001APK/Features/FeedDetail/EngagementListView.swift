import CoolapkKit
import SwiftUI

public struct EngagementListView: View {
    public enum Mode: Sendable {
        case likes(feedID: String)
        case forwards(feedID: String)
        case history(feedID: String)

        var title: String {
            switch self {
            case .likes: return "点赞的人"
            case .forwards: return "转发列表"
            case .history: return "编辑记录"
            }
        }
    }

    public let mode: Mode
    @Environment(AppState.self) private var appState
    @State private var users: [UserBrief] = []
    @State private var rows: [HomeFeedRow] = []
    @State private var isLoading = false
    @State private var page = 1
    @State private var hasMore = true

    public init(mode: Mode) {
        self.mode = mode
    }

    public var body: some View {
        Group {
            if isLoading && users.isEmpty && rows.isEmpty {
                ProgressView()
            } else if users.isEmpty && rows.isEmpty {
                ContentUnavailableView("暂无记录", systemImage: "list.bullet")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if case .likes = mode {
                            ForEach(Array(users.enumerated()), id: \.element.id) { idx, user in
                                UserRowView(user: user)
                                    .onAppear {
                                        if idx >= users.count - 4 { Task { await loadMore() } }
                                    }
                                Divider().padding(.leading, 16)
                            }
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                                HomeRowRenderer(row: row)
                                    .onAppear {
                                        if idx >= rows.count - 4 { Task { await loadMore() } }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadInitial() }
    }

    private func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        page = 1
        do {
            switch mode {
            case let .likes(feedID):
                users = try await API.likeList(feedID: feedID, page: 1)
                hasMore = !users.isEmpty
            case let .forwards(feedID):
                rows = try await API.forwardList(feedID: feedID, page: 1)
                hasMore = !rows.isEmpty
            case let .history(feedID):
                rows = try await API.changeHistory(feedID: feedID)
                hasMore = false
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let nextPage = page + 1
        do {
            switch mode {
            case let .likes(feedID):
                let next = try await API.likeList(feedID: feedID, page: nextPage)
                var seen = Set(users.map(\.id))
                let unique = next.filter { seen.insert($0.id).inserted }
                users.append(contentsOf: unique)
                hasMore = !unique.isEmpty
                if hasMore { page = nextPage }
            case let .forwards(feedID):
                let next = try await API.forwardList(feedID: feedID, page: nextPage)
                var seen = Set(rows.map(\.id))
                let unique = next.filter { seen.insert($0.id).inserted }
                rows.append(contentsOf: unique)
                hasMore = !unique.isEmpty
                if hasMore { page = nextPage }
            case .history:
                hasMore = false
            }
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}
