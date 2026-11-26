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

    public private(set) var rowsBySegment: [FollowSegment: [HomeFeedRow]] = [:]
    public private(set) var loadingSegments: Set<FollowSegment> = []
    public private(set) var loadedSegments: Set<FollowSegment> = []
    public private(set) var loadingMoreSegments: Set<FollowSegment> = []
    public private(set) var hasMoreBySegment: [FollowSegment: Bool] = [:]
    public private(set) var errorBySegment: [FollowSegment: String] = [:]

    private var pageBySegment: [FollowSegment: Int] = [:]
    private var activeTasks: [FollowSegment: Task<Void, Never>] = [:]
    private var cachedFollowedUIDs: Set<String> = []
    private var cachedFollowedUsers: [UserBrief] = []
    private var sessionMarker = -1

    public init() {}

    public func syncSessionIfNeeded(appState: AppState) {
        if sessionMarker != appState.sessionVersion {
            sessionMarker = appState.sessionVersion
            activeTasks.values.forEach { $0.cancel() }
            activeTasks.removeAll()
            rowsBySegment.removeAll()
            loadingSegments.removeAll()
            loadedSegments.removeAll()
            loadingMoreSegments.removeAll()
            hasMoreBySegment.removeAll()
            errorBySegment.removeAll()
            pageBySegment.removeAll()
            followedTopics = []
            selectedTopicTag = nil
            cachedFollowedUIDs = []
            cachedFollowedUsers = []
        }
    }

    public func loadInitial(segment targetSegment: FollowSegment, appState: AppState, force: Bool = false) async {
        syncSessionIfNeeded(appState: appState)
        if !force, let existing = rowsBySegment[targetSegment], !existing.isEmpty {
            return
        }
        activeTasks[targetSegment]?.cancel()
        pageBySegment[targetSegment] = 1
        hasMoreBySegment[targetSegment] = true
        errorBySegment[targetSegment] = nil
        loadingSegments.insert(targetSegment)

        let expectedSession = appState.sessionVersion
        let task = Task {
            await fetchPage(
                segment: targetSegment,
                page: 1,
                append: false,
                appState: appState,
                expectedSession: expectedSession
            )
        }
        activeTasks[targetSegment] = task
        await task.value
    }

    public func loadMore(segment targetSegment: FollowSegment, appState: AppState) async {
        guard !loadingSegments.contains(targetSegment),
              !loadingMoreSegments.contains(targetSegment),
              hasMoreBySegment[targetSegment] != false else { return }
        loadingMoreSegments.insert(targetSegment)
        let nextPage = (pageBySegment[targetSegment] ?? 1) + 1
        let expectedSession = appState.sessionVersion
        await fetchPage(
            segment: targetSegment,
            page: nextPage,
            append: true,
            appState: appState,
            expectedSession: expectedSession
        )
        loadingMoreSegments.remove(targetSegment)
    }

    private func fetchPage(
        segment targetSegment: FollowSegment,
        page: Int,
        append: Bool,
        appState: AppState,
        expectedSession: Int
    ) async {
        defer {
            if !append {
                loadingSegments.remove(targetSegment)
                loadedSegments.insert(targetSegment)
            }
        }
        do {
            let loaded: [HomeFeedRow]
            switch targetSegment {
            case .local:
                loaded = try await fetchLocalFollowRows(page: page, appState: appState)

            case .users:
                guard appState.accounts.isLoggedIn, let myUID = appState.accounts.activeUID else {
                    if !append { rowsBySegment[targetSegment] = [] }
                    hasMoreBySegment[targetSegment] = false
                    return
                }
                loaded = try await fetchFollowedUsersRows(myUID: myUID, page: page)

            case .topics:
                guard appState.accounts.isLoggedIn else {
                    if !append { rowsBySegment[targetSegment] = [] }
                    hasMoreBySegment[targetSegment] = false
                    return
                }
                if followedTopics.isEmpty {
                    followedTopics = (try? await API.followedTopics(page: 1)) ?? []
                    if selectedTopicTag == nil { selectedTopicTag = followedTopics.first?.title }
                }
                if let tag = selectedTopicTag, !tag.isEmpty {
                    loaded = try await API.topicFeeds(tag: tag, page: page)
                } else {
                    loaded = []
                }

            case .all:
                guard appState.accounts.isLoggedIn else {
                    loaded = try await fetchLocalFollowRows(page: page, appState: appState)
                    break
                }
                let raw = try await API.pageFeed(pageName: API.followPageName, page: page)
                loaded = raw.filter { row in
                    switch row {
                    case .linkBar, .linkList, .columnTabs: return false
                    default: return true
                    }
                }
            }

            guard !Task.isCancelled, expectedSession == appState.sessionVersion else { return }
            if append {
                let current = rowsBySegment[targetSegment] ?? []
                var existing = Set(current.map(\.id))
                let unique = loaded.filter { existing.insert($0.id).inserted }
                rowsBySegment[targetSegment] = current + unique
                if unique.isEmpty {
                    hasMoreBySegment[targetSegment] = false
                } else {
                    pageBySegment[targetSegment] = page
                }
            } else {
                rowsBySegment[targetSegment] = loaded
                hasMoreBySegment[targetSegment] = !loaded.isEmpty
                pageBySegment[targetSegment] = page
            }
        } catch {
            guard !Task.isCancelled, expectedSession == appState.sessionVersion else { return }
            let retried = await appState.handleAPIError(error)
            if retried && !append {
                await fetchPage(
                    segment: targetSegment,
                    page: page,
                    append: false,
                    appState: appState,
                    expectedSession: expectedSession
                )
                return
            }
            if !append { errorBySegment[targetSegment] = error.localizedDescription }
        }
    }

    private func fetchFollowedUsersRows(myUID: String, page: Int) async throws -> [HomeFeedRow] {
        if cachedFollowedUsers.isEmpty || page == 1 {
            let users = try await API.userList(uid: myUID, followers: false, page: 1)
            cachedFollowedUsers = users
            cachedFollowedUIDs = Set(users.map(\.id))
        }
        guard !cachedFollowedUsers.isEmpty else { return [] }

        // First try server follow feed filtered strictly to followed user UIDs (avoids topic injection).
        let candidateRows = (try? await API.pageFeed(pageName: API.followPageName, page: page, type: "user")) ?? []
        let filteredFeeds = candidateRows.filter { row in
            if case let .feed(feed) = row {
                return cachedFollowedUIDs.contains(feed.uid)
            }
            return false
        }
        if filteredFeeds.count >= 3 {
            return filteredFeeds
        }

        // Fall back to merging timelines directly from followed accounts so topic feeds never leak in.
        var collected: [HomeFeedRow] = filteredFeeds
        await withTaskGroup(of: [HomeFeedRow].self) { group in
            for user in cachedFollowedUsers.prefix(15) {
                group.addTask {
                    (try? await API.userFeeds(uid: user.id, page: page)) ?? []
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch.filter {
                    if case .feed = $0 { return true }
                    return false
                })
            }
        }
        var seen: Set<String> = []
        return collected
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private func fetchLocalFollowRows(page: Int, appState: AppState) async throws -> [HomeFeedRow] {
        let localUsers = appState.localFollow.users
        guard !localUsers.isEmpty else {
            hasMoreBySegment[.local] = false
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
