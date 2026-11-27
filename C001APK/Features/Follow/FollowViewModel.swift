import CoolapkKit
import Foundation
import Observation

public enum FollowSegment: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case users = "用户"
    case topics = "话题"
    case products = "数码"
    case apps = "应用"
    case dyh = "看看号"
    case collections = "收藏夹"
    case local = "本机关注"

    public var id: String { rawValue }

    public var requiresCloudLogin: Bool {
        switch self {
        case .all, .users, .local:
            return false
        case .topics, .products, .apps, .dyh, .collections:
            return true
        }
    }
}

@MainActor
@Observable
public final class FollowViewModel {
    public static let allTopicsChipID = "__all_topics__"
    public static let allProductsChipID = "__all_products__"

    public var segment: FollowSegment = .all
    public var rowsBySegment: [FollowSegment: [HomeFeedRow]] = [:]
    public var followedTopics: [TopicItem] = []
    public var selectedTopicTag: String = ""
    public var followedProducts: [ProductItem] = []
    public var selectedProductID: String = FollowViewModel.allProductsChipID
    public var loadingSegments: Set<FollowSegment> = []
    public var loadedSegments: Set<FollowSegment> = []
    public var loadingMoreSegments: Set<FollowSegment> = []
    public var errorBySegment: [FollowSegment: String] = [:]

    private var pageBySegment: [FollowSegment: Int] = [:]
    private var hasMoreBySegment: [FollowSegment: Bool] = [:]

    public init() {}

    public var rows: [HomeFeedRow] {
        rowsBySegment[segment] ?? []
    }

    public var isLoading: Bool {
        loadingSegments.contains(segment)
    }

    public var isLoadingMore: Bool {
        loadingMoreSegments.contains(segment)
    }

    public var errorMessage: String? {
        errorBySegment[segment]
    }

    public func loadInitial(segment targetSeg: FollowSegment? = nil, appState: AppState, force: Bool = false) async {
        let seg = targetSeg ?? segment
        if loadingSegments.contains(seg) { return }
        if !force, loadedSegments.contains(seg), !(rowsBySegment[seg]?.isEmpty ?? true) {
            return
        }

        loadingSegments.insert(seg)
        errorBySegment[seg] = nil
        pageBySegment[seg] = 1
        hasMoreBySegment[seg] = true
        defer {
            loadingSegments.remove(seg)
            loadedSegments.insert(seg)
        }

        do {
            let loadedRows = try await fetchRows(for: seg, page: 1, appState: appState)
            rowsBySegment[seg] = loadedRows
            hasMoreBySegment[seg] = !loadedRows.isEmpty
        } catch {
            if !Task.isCancelled {
                errorBySegment[seg] = error.localizedDescription
                _ = await appState.handleAPIError(error)
            }
        }
    }

    public func loadMore(segment targetSeg: FollowSegment? = nil, appState: AppState) async {
        let seg = targetSeg ?? segment
        guard (hasMoreBySegment[seg] ?? true),
              !loadingSegments.contains(seg),
              !loadingMoreSegments.contains(seg) else { return }
        loadingMoreSegments.insert(seg)
        defer { loadingMoreSegments.remove(seg) }

        let next = (pageBySegment[seg] ?? 1) + 1
        do {
            let nextRows = try await fetchRows(for: seg, page: next, appState: appState)
            let current = rowsBySegment[seg] ?? []
            var existingIDs = Set(current.map(\.id))
            let unique = nextRows.filter { existingIDs.insert($0.id).inserted }
            rowsBySegment[seg] = current + unique
            hasMoreBySegment[seg] = !unique.isEmpty
            if !unique.isEmpty {
                pageBySegment[seg] = next
            }
        } catch {
            // Keep existing rows on pagination failure
        }
    }

    private func fetchRows(for seg: FollowSegment, page: Int, appState: AppState) async throws -> [HomeFeedRow] {
        switch seg {
        case .local:
            return await fetchLocalFollowedTimeline(page: page, appState: appState)

        case .users:
            var combined: [HomeFeedRow] = []
            if appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad {
                let cloud = (try? await API.circleFollowFeed(page: page)) ?? []
                combined.append(contentsOf: cloud)
            }
            let local = await fetchLocalFollowedTimeline(page: page, appState: appState)
            combined.append(contentsOf: local)
            return deduplicateAndSortFeeds(combined)

        case .topics:
            guard appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad else { return [] }
            if followedTopics.isEmpty || page == 1 {
                let topics = (try? await API.followedTopics(page: 1)) ?? []
                if !topics.isEmpty {
                    followedTopics = topics
                }
                if selectedTopicTag.isEmpty {
                    selectedTopicTag = Self.allTopicsChipID
                }
            }
            if selectedTopicTag == Self.allTopicsChipID || selectedTopicTag.isEmpty {
                let topicList = (page == 1 && !followedTopics.isEmpty)
                    ? followedTopics
                    : ((try? await API.followedTopics(page: page)) ?? [])
                return topicList.map { .topic($0) }
            }
            return try await API.topicFeeds(tag: selectedTopicTag, page: page)

        case .products:
            guard appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad else { return [] }
            if followedProducts.isEmpty || page == 1 {
                let products = (try? await API.followedProducts(page: 1)) ?? []
                if !products.isEmpty {
                    followedProducts = products
                }
            }
            if selectedProductID != Self.allProductsChipID,
               let target = followedProducts.first(where: { $0.id == selectedProductID }) {
                return try await API.productFeeds(productID: target.id, title: target.title, page: page)
            }
            let list = (page == 1 && !followedProducts.isEmpty)
                ? followedProducts
                : ((try? await API.followedProducts(page: page)) ?? [])
            return list.map { .product($0) }

        case .apps:
            guard appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad else { return [] }
            let apps = try await API.followedApps(uid: appState.accounts.activeUID, page: page)
            return apps.map { .app($0) }

        case .dyh:
            guard appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad else { return [] }
            let dyhs = try await API.followedDyhs(page: page)
            return dyhs.map { .dyh($0) }

        case .collections:
            guard appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad else { return [] }
            let uid = appState.accounts.activeUID ?? ""
            let cols = try await API.collectionList(uid: uid, page: page)
            return cols.map { .collection($0) }

        case .all:
            var combined: [HomeFeedRow] = []
            if appState.accounts.isLoggedIn && appState.settings.enableCloudFollowLoad {
                let cloud = (try? await API.allFollowFeed(page: page)) ?? []
                combined.append(contentsOf: cloud)
            }
            let local = await fetchLocalFollowedTimeline(page: page, appState: appState)
            combined.append(contentsOf: local)
            return deduplicateAndSortFeeds(combined)
        }
    }

    private func fetchLocalFollowedTimeline(page: Int, appState: AppState) async -> [HomeFeedRow] {
        let localUsers = Array(appState.localFollow.users.prefix(15))
        guard !localUsers.isEmpty else { return [] }

        return await withTaskGroup(of: [HomeFeedRow].self) { group in
            for user in localUsers {
                group.addTask {
                    (try? await API.userFeeds(uid: user.uid, page: page)) ?? []
                }
            }
            var rows: [HomeFeedRow] = []
            for await sub in group {
                rows.append(contentsOf: sub)
            }
            return deduplicateAndSortFeeds(rows)
        }
    }

    private func deduplicateAndSortFeeds(_ rows: [HomeFeedRow]) -> [HomeFeedRow] {
        var seen = Set<String>()
        var feeds: [FeedItem] = []
        var others: [HomeFeedRow] = []

        for row in rows {
            guard seen.insert(row.id).inserted else { continue }
            if case let .feed(f) = row {
                feeds.append(f)
            } else {
                others.append(row)
            }
        }

        feeds.sort { ($0.dateline ?? .distantPast) > ($1.dateline ?? .distantPast) }
        return others + feeds.map { .feed($0) }
    }
}
