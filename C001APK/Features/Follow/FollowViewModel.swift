import CoolapkKit
import Foundation
import Observation

public enum FollowSegment: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case users = "关注用户"
    case topics = "话题"
    case local = "本机关注"

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class FollowViewModel {
    public var segment: FollowSegment = .all
    public var followedTopics: [TopicItem] = []
    public var selectedTopicTag: String?

    public private(set) var rows: [HomeFeedRow] = []
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var hasMore = true
    public private(set) var errorMessage: String?

    private var currentPage = 1
    private var activeTask: Task<Void, Never>?
    private var sessionMarker = -1

    public init() {}

    public func syncSessionIfNeeded(appState: AppState) {
        if sessionMarker != appState.sessionVersion {
            sessionMarker = appState.sessionVersion
            activeTask?.cancel()
            rows = []
            followedTopics = []
            selectedTopicTag = nil
            currentPage = 1
            hasMore = true
            errorMessage = nil
        }
    }

    public func loadInitial(appState: AppState, force: Bool = false) async {
        syncSessionIfNeeded(appState: appState)
        if !force && !rows.isEmpty { return }
        activeTask?.cancel()
        currentPage = 1
        hasMore = true
        errorMessage = nil
        isLoading = true

        let expectedSession = appState.sessionVersion
        let task = Task {
            await fetchPage(page: 1, append: false, appState: appState, expectedSession: expectedSession)
        }
        activeTask = task
        await task.value
    }

    public func loadMore(appState: AppState) async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        let expectedSession = appState.sessionVersion
        await fetchPage(page: nextPage, append: true, appState: appState, expectedSession: expectedSession)
        isLoadingMore = false
    }

    private func fetchPage(page: Int, append: Bool, appState: AppState, expectedSession: Int) async {
        defer { if !append { isLoading = false } }
        do {
            let loaded: [HomeFeedRow]
            switch segment {
            case .local:
                loaded = try await fetchLocalFollowRows(page: page, appState: appState)
            case .users:
                guard appState.accounts.isLoggedIn else {
                    if !append { rows = [] }
                    hasMore = false
                    return
                }
                loaded = try await API.pageFeed(pageName: API.followPageName, page: page, type: "circle")
            case .topics:
                guard appState.accounts.isLoggedIn else {
                    if !append { rows = [] }
                    hasMore = false
                    return
                }
                if followedTopics.isEmpty {
                    followedTopics = (try? await API.followedTopics(page: 1)) ?? []
                    if selectedTopicTag == nil { selectedTopicTag = followedTopics.first?.title }
                }
                if let tag = selectedTopicTag, !tag.isEmpty {
                    loaded = try await API.topicFeeds(tag: tag, page: page)
                } else {
                    loaded = try await API.pageFeed(pageName: API.followPageName, page: page, type: "tag")
                }
            case .all:
                guard appState.accounts.isLoggedIn else {
                    loaded = try await fetchLocalFollowRows(page: page, appState: appState)
                    break
                }
                async let userRowsTask = API.pageFeed(pageName: API.followPageName, page: page, type: "circle")
                async let tagRowsTask = API.pageFeed(pageName: API.followPageName, page: page, type: "tag")
                let userRows = (try? await userRowsTask) ?? []
                let tagRows = (try? await tagRowsTask) ?? []
                var seen: Set<String> = []
                let combined = (userRows + tagRows).filter { seen.insert($0.id).inserted }
                loaded = combined.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            }

            guard !Task.isCancelled, expectedSession == appState.sessionVersion else { return }
            if append {
                var existing = Set(rows.map(\.id))
                let unique = loaded.filter { existing.insert($0.id).inserted }
                rows.append(contentsOf: unique)
                if unique.isEmpty { hasMore = false } else { currentPage = page }
            } else {
                rows = loaded
                hasMore = !loaded.isEmpty
                currentPage = page
            }
        } catch {
            guard !Task.isCancelled, expectedSession == appState.sessionVersion else { return }
            let retried = await appState.handleAPIError(error)
            if retried && !append {
                await fetchPage(page: page, append: false, appState: appState, expectedSession: expectedSession)
                return
            }
            if !append { errorMessage = error.localizedDescription }
        }
    }

    private func fetchLocalFollowRows(page: Int, appState: AppState) async throws -> [HomeFeedRow] {
        let localUsers = appState.localFollow.users
        guard !localUsers.isEmpty else {
            hasMore = false
            return []
        }
        var collected: [HomeFeedRow] = []
        await withTaskGroup(of: [HomeFeedRow].self) { group in
            for user in localUsers.prefix(15) {
                group.addTask {
                    (try? await API.userFeeds(uid: user.uid, page: page)) ?? []
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch)
            }
        }
        var seen: Set<String> = []
        return collected
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}
