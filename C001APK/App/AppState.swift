import CoolapkKit
import Foundation
import Observation
import SwiftUI
import UIKit

public struct CaptchaSessionRequest: Identifiable, Sendable {
    public let id = UUID()
    public let challenge: CaptchaChallenge
}

@MainActor
@Observable
public final class AppState {
    public let accounts = AccountStore()
    public let settings = SettingsStore()
    public let localFollow = LocalFollowStore()
    public let blacklist = BlacklistStore()
    public let contentFilter = ContentFilterService()
    public let historyAndFav = HistoryAndFavStore()

    public var selectedTab: RootTab = .home
    public var homeNavigationPath: [AppRoute] = []
    public var partitionNavigationPath: [AppRoute] = []
    public var followNavigationPath: [AppRoute] = []
    public var swipeNavigationPath: [AppRoute] = []
    public var profileNavigationPath: [AppRoute] = []
    public var searchNavigationPath: [AppRoute] = []

    /// Incremented whenever the active account changes so views/tasks reset cleanly.
    public private(set) var sessionVersion: Int = 0
    public private(set) var isSessionBootstrapped = false
    public var badge = NotificationBadge()
    public var currentUserProfile: UserProfile?

    /// Persistent & session read/unread state tracking for notifications and private message threads.
    public private(set) var readStateRevision: Int = 0
    @ObservationIgnored private var readNotificationIDs: Set<String> = []
    @ObservationIgnored private var unreadOverrideNotificationIDs: Set<String> = []
    @ObservationIgnored private var readThreadTimestamps: [String: TimeInterval] = [:]
    @ObservationIgnored private var unreadOverrideThreadIDs: Set<String> = []
    @ObservationIgnored private var clearedEndpointBadges: Set<String> = []

    public var toastMessage: String?
    private var toastTask: Task<Void, Never>?

    public var showLoginSheet = false
    public var showWebLoginSheet = false
    public var showOnboarding = false
    public var composeMode: ComposeMode?
    public var mediaViewer: MediaViewerPresentation?
    public var activeCaptchaRequest: CaptchaSessionRequest?
    private var captchaContinuations: [CheckedContinuation<String?, Never>] = []

    public var searchQuery: String = ""
    public var homeDoubleTapTrigger: Int = 0
    public var followDoubleTapTrigger: Int = 0
    public var swipeDoubleTapTrigger: Int = 0
    public var feedRefreshTrigger: Int = 0
    public var pageTabSelections: [String: String] = [:] {
        didSet {
            if pageTabSelections.count > 120 {
                let overflow = pageTabSelections.count - 80
                for key in pageTabSelections.keys.prefix(overflow) {
                    pageTabSelections.removeValue(forKey: key)
                }
            }
        }
    }
    public var homeSelectedTab: HomeTabType = .feed
    public var favoritePickerFeed: FeedItem?

    /// Session-scoped entity caches so navigating across screens pre-fills titles, avatars, and metadata on frame 0.
    @ObservationIgnored private var cachedFeedDetails: [String: FeedItem] = [:]
    @ObservationIgnored private var cachedFeedOrder: [String] = []
    @ObservationIgnored public private(set) var verifiedDetailIDs: Set<String> = []
    @ObservationIgnored private var cachedUserProfiles: [String: UserProfile] = [:]
    @ObservationIgnored private var cachedTopics: [String: TopicItem] = [:]
    @ObservationIgnored private var cachedProducts: [String: ProductItem] = [:]
    @ObservationIgnored private var cachedApps: [String: AppItem] = [:]
    @ObservationIgnored private var cachedCollections: [String: CollectionItem] = [:]
    @ObservationIgnored private var cachedDyhs: [String: DyhItem] = [:]
    @ObservationIgnored private var knownFollowedEntityKeys: Set<String> = []
    @ObservationIgnored private var modalPushStack: [(id: UUID, handler: (AppRoute) -> Void)] = []

    @ObservationIgnored private var lastCheckedPasteboardChangeCount: Int = -1
    @ObservationIgnored private var lastHandledClipboardLinkKey: String = UserDefaults.standard.string(forKey: "c001apk.lastHandledClipboardLinkKey.v1") ?? ""

    private static let readNotificationsDefaultsKey = "c001apk.readNotifications.v1"
    private static let unreadNotificationsDefaultsKey = "c001apk.unreadNotifications.v1"
    private static let readThreadsDefaultsKey = "c001apk.readThreads.v1"
    private static let unreadThreadsDefaultsKey = "c001apk.unreadThreads.v1"
    private static let lastClipboardKeyDefaultsKey = "c001apk.lastHandledClipboardLinkKey.v1"

    public init() {
        self.showOnboarding = !settings.onboardingCompleted
        loadPersistedReadState()
    }

    // MARK: - Cross-Screen Entity Caching

    public func cachedFeedDetail(id: String) -> FeedItem? {
        cachedFeedDetails[id]
    }

    public func cacheFeedDetail(_ feed: FeedItem, verified: Bool) {
        let id = feed.effectiveFeedID
        guard !id.isEmpty else { return }
        if cachedFeedDetails[id] == nil {
            cachedFeedOrder.append(id)
            if cachedFeedOrder.count > 120 {
                let dropCount = cachedFeedOrder.count - 80
                for evicted in cachedFeedOrder.prefix(dropCount) {
                    cachedFeedDetails.removeValue(forKey: evicted)
                    verifiedDetailIDs.remove(evicted)
                }
                cachedFeedOrder.removeFirst(dropCount)
            }
        }
        cachedFeedDetails[id] = feed
        if verified {
            verifiedDetailIDs.insert(id)
        }
    }

    public func cachedUserProfile(uid: String) -> UserProfile? {
        let clean = (uid.removingPercentEncoding ?? uid).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let direct = cachedUserProfiles[clean] {
            return direct
        }
        if let current = currentUserProfile, (current.id == clean || current.username == clean) {
            return current
        }
        return cachedUserProfiles.values.first { $0.username == clean }
    }

    public func cacheUserProfile(_ profile: UserProfile) {
        if !profile.id.isEmpty {
            cachedUserProfiles[profile.id] = profile
        }
        if !profile.username.isEmpty {
            cachedUserProfiles[profile.username] = profile
        }
    }

    public func markEntityFollowed(kind: String, keys: [String], isFollowed: Bool) {
        for raw in keys {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let k = "\(kind):\(trimmed.lowercased())"
            if isFollowed {
                knownFollowedEntityKeys.insert(k)
            } else {
                knownFollowedEntityKeys.remove(k)
            }
        }
    }

    public func isEntityKnownFollowed(kind: String, keys: [String]) -> Bool {
        for raw in keys {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if knownFollowedEntityKeys.contains("\(kind):\(trimmed.lowercased())") {
                return true
            }
        }
        return false
    }

    public func cachedTopicDetail(tag: String) -> TopicItem? {
        let clean = TopicItem.cleanTitle(tag)
        if var found = cachedTopics[clean] ?? cachedTopics[tag] {
            if !found.isFollowed && isEntityKnownFollowed(kind: "topic", keys: [found.id, clean, found.title, tag]) {
                found.isFollowed = true
            }
            return found
        }
        return nil
    }

    public func cacheTopicDetail(_ topic: TopicItem, forTag tag: String? = nil, explicitFollowChange: Bool = false) {
        let clean = TopicItem.cleanTitle(topic.title)
        let tagClean = tag.map(TopicItem.cleanTitle) ?? ""
        let keys = [topic.id, clean, topic.title, tagClean].filter { !$0.isEmpty }
        var resolved = topic
        if topic.isFollowed {
            markEntityFollowed(kind: "topic", keys: keys, isFollowed: true)
        } else if explicitFollowChange {
            markEntityFollowed(kind: "topic", keys: keys, isFollowed: false)
        } else if isEntityKnownFollowed(kind: "topic", keys: keys)
            || cachedTopics[clean]?.isFollowed == true
            || (!tagClean.isEmpty && cachedTopics[tagClean]?.isFollowed == true) {
            resolved.isFollowed = true
        }
        if !clean.isEmpty {
            cachedTopics[clean] = resolved
        }
        if !tagClean.isEmpty {
            cachedTopics[tagClean] = resolved
        }
        if !resolved.id.isEmpty {
            cachedTopics[resolved.id] = resolved
        }
    }

    public func cachedProductDetail(id: String) -> ProductItem? {
        if var found = cachedProducts[id] {
            if !found.isFollowed && isEntityKnownFollowed(kind: "product", keys: [id, found.id, found.title]) {
                found.isFollowed = true
            }
            return found
        }
        return nil
    }

    public func cacheProductDetail(_ product: ProductItem, explicitFollowChange: Bool = false) {
        guard !product.id.isEmpty else { return }
        let keys = [product.id, product.title].filter { !$0.isEmpty }
        var resolved = product
        if product.isFollowed {
            markEntityFollowed(kind: "product", keys: keys, isFollowed: true)
        } else if explicitFollowChange {
            markEntityFollowed(kind: "product", keys: keys, isFollowed: false)
        } else if isEntityKnownFollowed(kind: "product", keys: keys)
            || cachedProducts[product.id]?.isFollowed == true {
            resolved.isFollowed = true
        }
        cachedProducts[resolved.id] = resolved
    }

    public func cachedAppDetail(id: String) -> AppItem? {
        if var found = cachedApps[id] {
            if !found.isFollowed && isEntityKnownFollowed(kind: "app", keys: [id, found.id, found.packageName, found.title]) {
                found.isFollowed = true
            }
            return found
        }
        return nil
    }

    public func cacheAppDetail(_ app: AppItem, explicitFollowChange: Bool = false) {
        let keys = [app.id, app.packageName, app.title].filter { !$0.isEmpty }
        guard !keys.isEmpty else { return }
        var resolved = app
        if app.isFollowed {
            markEntityFollowed(kind: "app", keys: keys, isFollowed: true)
        } else if explicitFollowChange {
            markEntityFollowed(kind: "app", keys: keys, isFollowed: false)
        } else if isEntityKnownFollowed(kind: "app", keys: keys)
            || (!app.id.isEmpty && cachedApps[app.id]?.isFollowed == true)
            || (!app.packageName.isEmpty && cachedApps[app.packageName]?.isFollowed == true) {
            resolved.isFollowed = true
        }
        if !resolved.id.isEmpty {
            cachedApps[resolved.id] = resolved
        }
        if !resolved.packageName.isEmpty {
            cachedApps[resolved.packageName] = resolved
        }
    }

    public func cachedCollectionDetail(id: String) -> CollectionItem? {
        if var found = cachedCollections[id] {
            if !found.isFollowed && isEntityKnownFollowed(kind: "collection", keys: [id, found.id, found.title]) {
                found.isFollowed = true
            }
            return found
        }
        return nil
    }

    public func cacheCollectionDetail(_ collection: CollectionItem, explicitFollowChange: Bool = false) {
        guard !collection.id.isEmpty else { return }
        let keys = [collection.id, collection.title].filter { !$0.isEmpty }
        var resolved = collection
        if resolved.logo.isEmpty {
            if let existingLogo = cachedCollections[collection.id]?.logo, !existingLogo.isEmpty {
                resolved.logo = existingLogo
            } else if let cachedCloudLogo = historyAndFav.cachedCloudCollections.first(where: { $0.id == collection.id })?.logo, !cachedCloudLogo.isEmpty {
                resolved.logo = cachedCloudLogo
            }
        }
        if collection.isFollowed {
            markEntityFollowed(kind: "collection", keys: keys, isFollowed: true)
        } else if explicitFollowChange {
            markEntityFollowed(kind: "collection", keys: keys, isFollowed: false)
        } else if isEntityKnownFollowed(kind: "collection", keys: keys)
            || cachedCollections[collection.id]?.isFollowed == true {
            resolved.isFollowed = true
        }
        cachedCollections[resolved.id] = resolved
    }

    public func cachedDyhDetail(id: String) -> DyhItem? {
        if var found = cachedDyhs[id] {
            if !found.isFollowed && isEntityKnownFollowed(kind: "dyh", keys: [id, found.id, found.title]) {
                found.isFollowed = true
            }
            return found
        }
        return nil
    }

    public func cacheDyhDetail(_ dyh: DyhItem, explicitFollowChange: Bool = false) {
        guard !dyh.id.isEmpty else { return }
        let keys = [dyh.id, dyh.title].filter { !$0.isEmpty }
        var resolved = dyh
        if dyh.isFollowed {
            markEntityFollowed(kind: "dyh", keys: keys, isFollowed: true)
        } else if explicitFollowChange {
            markEntityFollowed(kind: "dyh", keys: keys, isFollowed: false)
        } else if isEntityKnownFollowed(kind: "dyh", keys: keys)
            || cachedDyhs[dyh.id]?.isFollowed == true {
            resolved.isFollowed = true
        }
        cachedDyhs[resolved.id] = resolved
    }

    // MARK: - Message & Notification Read / Unread State

    private func loadPersistedReadState() {
        let defaults = UserDefaults.standard
        if let arr = defaults.stringArray(forKey: Self.readNotificationsDefaultsKey) {
            readNotificationIDs = Set(arr)
        }
        if let arr = defaults.stringArray(forKey: Self.unreadNotificationsDefaultsKey) {
            unreadOverrideNotificationIDs = Set(arr)
        }
        if let dict = defaults.dictionary(forKey: Self.readThreadsDefaultsKey) as? [String: TimeInterval] {
            readThreadTimestamps = dict
        }
        if let arr = defaults.stringArray(forKey: Self.unreadThreadsDefaultsKey) {
            unreadOverrideThreadIDs = Set(arr)
        }
    }

    private func persistReadState() {
        let defaults = UserDefaults.standard
        defaults.set(Array(readNotificationIDs.suffix(800)), forKey: Self.readNotificationsDefaultsKey)
        defaults.set(Array(unreadOverrideNotificationIDs.suffix(400)), forKey: Self.unreadNotificationsDefaultsKey)
        defaults.set(readThreadTimestamps, forKey: Self.readThreadsDefaultsKey)
        defaults.set(Array(unreadOverrideThreadIDs.suffix(400)), forKey: Self.unreadThreadsDefaultsKey)
    }

    public func isNotificationRead(_ item: NotificationItem) -> Bool {
        _ = readStateRevision
        if unreadOverrideNotificationIDs.contains(item.id) {
            return false
        }
        if readNotificationIDs.contains(item.id) {
            return true
        }
        return item.isRead
    }

    public func setNotificationRead(_ item: NotificationItem, isRead: Bool, endpointType: String = "") {
        if isRead {
            let wasUnread = !isNotificationRead(item)
            unreadOverrideNotificationIDs.remove(item.id)
            readNotificationIDs.insert(item.id)
            if wasUnread {
                decrementBadge(forEndpointType: endpointType, by: 1)
            }
        } else {
            let wasRead = isNotificationRead(item)
            readNotificationIDs.remove(item.id)
            unreadOverrideNotificationIDs.insert(item.id)
            if wasRead {
                incrementBadge(forEndpointType: endpointType, by: 1)
            }
        }
        readStateRevision &+= 1
        persistReadState()
    }

    public func effectiveThreadUnreadCount(_ thread: MessageThread) -> Int {
        _ = readStateRevision
        let keys = [thread.id, thread.ukey, thread.uid].filter { !$0.isEmpty }
        if keys.contains(where: { unreadOverrideThreadIDs.contains($0) }) {
            return max(1, thread.unreadNum)
        }
        let threadTime = thread.dateline?.timeIntervalSince1970 ?? 0
        for key in keys {
            if let readAt = readThreadTimestamps[key], readAt >= threadTime {
                return 0
            }
        }
        return max(0, thread.unreadNum)
    }

    public func isThreadRead(_ thread: MessageThread) -> Bool {
        effectiveThreadUnreadCount(thread) == 0
    }

    public func setThreadRead(_ thread: MessageThread, isRead: Bool) {
        let prevUnread = effectiveThreadUnreadCount(thread)
        let keys = [thread.id, thread.ukey, thread.uid].filter { !$0.isEmpty }
        if isRead {
            let stamp = max(Date().timeIntervalSince1970, (thread.dateline?.timeIntervalSince1970 ?? 0) + 1)
            for key in keys {
                unreadOverrideThreadIDs.remove(key)
                readThreadTimestamps[key] = stamp
            }
            if prevUnread > 0 {
                badge.message = max(0, badge.message - prevUnread)
            }
            Task { await API.markMessageThreadRead(ukey: thread.ukey) }
        } else {
            for key in keys {
                readThreadTimestamps.removeValue(forKey: key)
                unreadOverrideThreadIDs.insert(key)
            }
            if prevUnread == 0 {
                badge.message += 1
            }
        }
        readStateRevision &+= 1
        persistReadState()
    }

    public func markThreadReadByUkey(ukey: String, uid: String) {
        let keys = [ukey, uid].filter { !$0.isEmpty }
        guard !keys.isEmpty else { return }
        let stamp = Date().timeIntervalSince1970 + 1
        for key in keys {
            unreadOverrideThreadIDs.remove(key)
            readThreadTimestamps[key] = stamp
        }
        readStateRevision &+= 1
        persistReadState()
        Task { await API.markMessageThreadRead(ukey: ukey) }
    }

    public func markSegmentRead(
        endpointType: String,
        threads: [MessageThread],
        notifications: [NotificationItem]
    ) {
        if endpointType.isEmpty {
            let now = Date().timeIntervalSince1970 + 1
            for thread in threads {
                for key in [thread.id, thread.ukey, thread.uid] where !key.isEmpty {
                    unreadOverrideThreadIDs.remove(key)
                    readThreadTimestamps[key] = max(now, (thread.dateline?.timeIntervalSince1970 ?? 0) + 1)
                }
                if thread.unreadNum > 0 {
                    Task { await API.markMessageThreadRead(ukey: thread.ukey) }
                }
            }
            badge.message = 0
            clearedEndpointBadges.insert("chat")
        } else {
            for item in notifications {
                unreadOverrideNotificationIDs.remove(item.id)
                readNotificationIDs.insert(item.id)
            }
            badge.clear(forEndpointType: endpointType)
            clearedEndpointBadges.insert(endpointType)
            Task { await API.clearNotificationCount(type: endpointType) }
        }
        readStateRevision &+= 1
        persistReadState()
    }

    public func markAllMessagesAndNotificationsRead(
        threads: [MessageThread],
        notificationsBySegment: [String: [NotificationItem]]
    ) {
        let now = Date().timeIntervalSince1970 + 1
        for thread in threads {
            for key in [thread.id, thread.ukey, thread.uid] where !key.isEmpty {
                unreadOverrideThreadIDs.remove(key)
                readThreadTimestamps[key] = max(now, (thread.dateline?.timeIntervalSince1970 ?? 0) + 1)
            }
            if thread.unreadNum > 0 {
                Task { await API.markMessageThreadRead(ukey: thread.ukey) }
            }
        }
        unreadOverrideThreadIDs.removeAll()
        for (_, items) in notificationsBySegment {
            for item in items {
                unreadOverrideNotificationIDs.remove(item.id)
                readNotificationIDs.insert(item.id)
            }
        }
        unreadOverrideNotificationIDs.removeAll()
        badge.clearAll()
        clearedEndpointBadges = ["chat", "commentMeList", "atMeList", "feedLikeList", "contactsFollowList", "list"]
        readStateRevision &+= 1
        persistReadState()
        Task {
            await API.clearNotificationCount()
        }
    }

    public var hasUnreadMessages: Bool {
        _ = readStateRevision
        if !unreadOverrideNotificationIDs.isEmpty || !unreadOverrideThreadIDs.isEmpty {
            return true
        }
        return badge.total > 0
    }

    private func decrementBadge(forEndpointType endpointType: String, by amount: Int) {
        switch endpointType {
        case "": badge.message = max(0, badge.message - amount)
        case "commentMeList", "commentMe": badge.commentMe = max(0, badge.commentMe - amount)
        case "atMeList", "atMe":
            if badge.atMe > 0 {
                badge.atMe = max(0, badge.atMe - amount)
            } else {
                badge.atCommentMe = max(0, badge.atCommentMe - amount)
            }
        case "feedLikeList", "feedLike": badge.feedLike = max(0, badge.feedLike - amount)
        case "contactsFollowList", "contactsFollow": badge.contactsFollow = max(0, badge.contactsFollow - amount)
        case "list", "notification": badge.notification = max(0, badge.notification - amount)
        default: break
        }
    }

    private func incrementBadge(forEndpointType endpointType: String, by amount: Int) {
        switch endpointType {
        case "": badge.message += amount
        case "commentMeList", "commentMe": badge.commentMe += amount
        case "atMeList", "atMe": badge.atMe += amount
        case "feedLikeList", "feedLike": badge.feedLike += amount
        case "contactsFollowList", "contactsFollow": badge.contactsFollow += amount
        case "list", "notification": badge.notification += amount
        default: badge.notification += amount
        }
    }

    private func applyLocalBadgeOverrides(to incoming: NotificationBadge) -> NotificationBadge {
        var adjusted = incoming
        for cleared in clearedEndpointBadges {
            if cleared == "chat" {
                adjusted.message = 0
            } else {
                adjusted.clear(forEndpointType: cleared)
            }
        }
        if !unreadOverrideThreadIDs.isEmpty {
            adjusted.message = max(adjusted.message, unreadOverrideThreadIDs.count)
        }
        if !unreadOverrideNotificationIDs.isEmpty && adjusted.total == 0 {
            adjusted.notification = unreadOverrideNotificationIDs.count
        }
        return adjusted
    }

    public func registerModalPush(id: UUID, handler: @escaping (AppRoute) -> Void) {
        modalPushStack.removeAll { $0.id == id }
        modalPushStack.append((id: id, handler: handler))
    }

    public func unregisterModalPush(id: UUID) {
        modalPushStack.removeAll { $0.id == id }
    }

    public func bootstrap() async {
        await ImagePipeline.shared.updateUserAgent(settings.protocolParameters.userAgent)
        await ImagePipeline.shared.updateMaxDiskBytes(Int64(max(50, settings.maxImageCacheMB)) * 1024 * 1024)
        await accounts.restoreActiveSessionIntoClient(
            parameters: settings.protocolParameters,
            isInitialBootstrap: true
        )
        isSessionBootstrapped = true
        if settings.onboardingCompleted,
           settings.autoAcquireSzlmOnLaunch,
           settings.protocolParameters.szlmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.settings.acquireSzlmID()
            }
        }
        await refreshLoginAndBadge()
    }

    public func refreshLoginAndBadge() async {
        guard let active = accounts.activeAccount else {
            currentUserProfile = nil
            badge = NotificationBadge()
            return
        }
        do {
            let check = try await API.checkLoginInfo(expectedUID: active.uid)
            if check.explicitlyInvalid {
                await accounts.expireCurrent()
                currentUserProfile = nil
                badge = NotificationBadge()
                notifyAccountSessionChanged()
                showToast("登录状态已过期，请重新登录")
                return
            }
            if !check.token.isEmpty {
                await accounts.refreshActiveCredentials(
                    uid: check.uid.isEmpty ? active.uid : check.uid,
                    username: check.username,
                    token: check.token
                )
            }
            async let profileTask = API.userProfile(uid: active.uid)
            async let badgeTask = API.badge()
            if let profile = try? await profileTask {
                currentUserProfile = profile
                cacheUserProfile(profile)
                accounts.updateProfile(profile)
            }
            if let newBadge = try? await badgeTask {
                badge = applyLocalBadgeOverrides(to: newBadge)
            }
        } catch APIError.expired, APIError.unauthorized {
            await accounts.expireCurrent()
            currentUserProfile = nil
            badge = NotificationBadge()
            notifyAccountSessionChanged()
            showToast("登录状态已过期，请重新登录")
        } catch {
            // Keep existing cached session on transient offline startup or captcha challenge.
        }
    }

    public func refreshBadgeOnly() async {
        guard accounts.isLoggedIn else {
            badge = NotificationBadge()
            return
        }
        if let updated = try? await API.badge() {
            badge = applyLocalBadgeOverrides(to: updated)
        }
    }

    public func notifyAccountSessionChanged() {
        sessionVersion += 1
        cachedFeedDetails.removeAll()
        cachedFeedOrder.removeAll()
        verifiedDetailIDs.removeAll()
        cachedUserProfiles.removeAll()
        cachedTopics.removeAll()
        cachedProducts.removeAll()
        cachedApps.removeAll()
        cachedCollections.removeAll()
        cachedDyhs.removeAll()
        clearedEndpointBadges.removeAll()
        homeNavigationPath.removeAll()
        partitionNavigationPath.removeAll()
        followNavigationPath.removeAll()
        swipeNavigationPath.removeAll()
        profileNavigationPath.removeAll()
        searchNavigationPath.removeAll()
        Task { await refreshLoginAndBadge() }
    }

    // MARK: - Navigation & Link Routing

    public func push(_ route: AppRoute) {
        if let activeModal = modalPushStack.last {
            activeModal.handler(route)
            return
        }
        switch selectedTab {
        case .home: homeNavigationPath.append(route)
        case .partition: partitionNavigationPath.append(route)
        case .follow: followNavigationPath.append(route)
        case .swipe: swipeNavigationPath.append(route)
        case .profile: profileNavigationPath.append(route)
        case .search: searchNavigationPath.append(route)
        }
    }

    public func openRawLink(_ raw: String, title: String? = nil, transitionID: String? = nil) {
        if raw.hasPrefix("coolapk-internal://route?target="),
           let comp = URLComponents(string: raw),
           let target = comp.queryItems?.first(where: { $0.name == "target" })?.value {
            openRawLink(target, title: title, transitionID: transitionID)
            return
        }
        guard let resolved = FeedLink.resolve(raw) else { return }
        let route = AppRoute.from(feedLink: resolved, preferredTitle: title, transitionID: transitionID)
        if case let .web(url) = route, settings.openInBrowser {
            UIApplication.shared.open(url)
            return
        }
        if isCurrentTopRouteMatching(resolved) {
            return
        }
        push(route)
    }

    private func currentActiveNavigationPath() -> [AppRoute] {
        switch selectedTab {
        case .home: return homeNavigationPath
        case .partition: return partitionNavigationPath
        case .follow: return followNavigationPath
        case .swipe: return swipeNavigationPath
        case .profile: return profileNavigationPath
        case .search: return searchNavigationPath
        }
    }

    private func isCurrentTopRouteMatching(_ link: FeedLink) -> Bool {
        guard let top = currentActiveNavigationPath().last else { return false }
        switch (top, link) {
        case let (.feed(id1, _, _), .feed(id2)),
             let (.feed(id1, _, _), .question(id2)),
             let (.feed(id1, _, _), .vote(id2)):
            return id1 == id2
        case let (.topic(t1, _), .topic(t2)):
            return TopicItem.cleanTitle(t1).lowercased() == TopicItem.cleanTitle(t2).lowercased()
        case let (.user(u1, _, _, _, _), .user(u2)):
            return u1.lowercased() == u2.lowercased()
        case let (.product(p1, _, _), .product(p2)):
            return p1 == p2
        case let (.app(a1, _, _), .app(a2)):
            return a1.lowercased() == a2.lowercased()
        case let (.collection(c1, _, _), .collection(c2)):
            return c1 == c2
        case let (.dyh(d1, _, _), .dyh(d2)):
            return d1 == d2
        case let (.event(e1, _, _), .event(e2)):
            return e1 == e2
        default:
            return false
        }
    }

    public func copyLinkToPasteboard(_ urlString: String, toastMessage: String = "已复制链接") {
        if let extracted = FeedLink.extractFirstCoolapkLink(from: urlString) {
            lastHandledClipboardLinkKey = extracted.link.canonicalKey
            UserDefaults.standard.set(lastHandledClipboardLinkKey, forKey: Self.lastClipboardKeyDefaultsKey)
        }
        UIPasteboard.general.string = urlString
        lastCheckedPasteboardChangeCount = UIPasteboard.general.changeCount
        showToast(toastMessage)
    }

    public func handleIncomingOpenURL(_ url: URL) {
        let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if let extracted = FeedLink.extractFirstCoolapkLink(from: raw) {
            lastHandledClipboardLinkKey = extracted.link.canonicalKey
            UserDefaults.standard.set(lastHandledClipboardLinkKey, forKey: Self.lastClipboardKeyDefaultsKey)
        }
        if mediaViewer != nil {
            mediaViewer = nil
        }
        if composeMode != nil {
            composeMode = nil
        }
        openRawLink(raw)
    }

    public func checkClipboardForCoolapkLink() {
        guard settings.autoDetectClipboardLink, !showOnboarding else { return }
        let pb = UIPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastCheckedPasteboardChangeCount else { return }
        lastCheckedPasteboardChangeCount = currentCount

        guard pb.hasStrings || pb.hasURLs else { return }
        let candidateText: String = {
            if let str = pb.string, !str.isEmpty { return str }
            if let url = pb.url { return url.absoluteString }
            return ""
        }()
        guard !candidateText.isEmpty,
              let extracted = FeedLink.extractFirstCoolapkLink(from: candidateText) else {
            return
        }

        let key = extracted.link.canonicalKey
        guard !key.isEmpty, key != lastHandledClipboardLinkKey else { return }
        lastHandledClipboardLinkKey = key
        UserDefaults.standard.set(key, forKey: Self.lastClipboardKeyDefaultsKey)

        guard !isCurrentTopRouteMatching(extracted.link) else { return }
        openRawLink(extracted.rawURL)
        showToast("已从剪贴板打开酷安链接")
    }

    public func openMedia(_ items: [FeedMedia], at index: Int, sourcePrefix: String? = nil) {
        guard !items.isEmpty else { return }
        mediaViewer = MediaViewerPresentation(items: items, initialIndex: index, sourcePrefix: sourcePrefix)
    }

    // MARK: - Error & Captcha Handling

    @discardableResult
    public func handleAPIError(_ error: Error, allowCaptchaPrompt: Bool = true) async -> Bool {
        if error is CancellationError || (error as? APIError).map({
            if case .sessionChanged = $0 { return true }
            return false
        }) == true {
            return false
        }

        if case let APIError.captchaRequired(challenge, _) = error {
            if challenge.field.isEmpty,
               settings.autoAcquireSzlmOnLaunch,
               settings.protocolParameters.szlmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               settings.szlmNextAllowedAt == nil,
               (try? await settings.acquireSzlmID()) != nil {
                return true
            }
            guard allowCaptchaPrompt else { return false }
            let proof = await requestCaptchaVerification(challenge: challenge)
            if let proof, !proof.isEmpty {
                await CoolapkClient.shared.setCaptchaProof(proof, field: challenge.field)
                return true // Caller can retry request immediately.
            }
            return false
        }

        if case APIError.unauthorized = error {
            showToast("请先登录酷安账号")
            showLoginSheet = true
            return false
        }

        if case APIError.expired = error {
            await accounts.expireCurrent()
            notifyAccountSessionChanged()
            showToast("登录状态已过期，请重新登录")
            showLoginSheet = true
            return false
        }

        showToast(error.localizedDescription)
        return false
    }

    public func requestCaptchaVerification(challenge: CaptchaChallenge) async -> String? {
        await withCheckedContinuation { continuation in
            captchaContinuations.append(continuation)
            if activeCaptchaRequest == nil {
                activeCaptchaRequest = CaptchaSessionRequest(challenge: challenge)
            }
        }
    }

    public func completeCaptcha(validateToken: String?) {
        let challenge = activeCaptchaRequest?.challenge
        activeCaptchaRequest = nil
        let proof = validateToken.flatMap { challenge?.proof(from: $0) }
        let pending = captchaContinuations
        captchaContinuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: proof)
        }
    }

    // MARK: - Toast

    public func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }
}
