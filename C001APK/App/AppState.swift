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
    public var followNavigationPath: [AppRoute] = []
    public var profileNavigationPath: [AppRoute] = []
    public var searchNavigationPath: [AppRoute] = []

    /// Incremented whenever the active account changes so views/tasks reset cleanly.
    public private(set) var sessionVersion: Int = 0
    public private(set) var isSessionBootstrapped = false
    public var badge = NotificationBadge()
    public var currentUserProfile: UserProfile?

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
    public var feedRefreshTrigger: Int = 0
    public var pageTabSelections: [String: String] = [:]
    public var homeSelectedTab: HomeTabType = .feed
    public var favoritePickerFeed: FeedItem?

    public init() {
        self.showOnboarding = !settings.onboardingCompleted
    }

    public func bootstrap() async {
        await ImagePipeline.shared.updateUserAgent(settings.protocolParameters.userAgent)
        await accounts.restoreActiveSessionIntoClient(
            parameters: settings.protocolParameters,
            isInitialBootstrap: true
        )
        isSessionBootstrapped = true
        if settings.autoAcquireSzlmOnLaunch,
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
                accounts.updateProfile(profile)
            }
            if let newBadge = try? await badgeTask {
                badge = newBadge
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
            badge = updated
        }
    }

    public func notifyAccountSessionChanged() {
        sessionVersion += 1
        homeNavigationPath.removeAll()
        followNavigationPath.removeAll()
        profileNavigationPath.removeAll()
        searchNavigationPath.removeAll()
        Task { await refreshLoginAndBadge() }
    }

    // MARK: - Navigation & Link Routing

    public func push(_ route: AppRoute) {
        switch selectedTab {
        case .home: homeNavigationPath.append(route)
        case .follow: followNavigationPath.append(route)
        case .profile: profileNavigationPath.append(route)
        case .search: searchNavigationPath.append(route)
        }
    }

    public func openRawLink(_ raw: String, transitionID: String? = nil) {
        if raw.hasPrefix("coolapk-internal://route?target="),
           let comp = URLComponents(string: raw),
           let target = comp.queryItems?.first(where: { $0.name == "target" })?.value {
            openRawLink(target, transitionID: transitionID)
            return
        }
        guard let resolved = FeedLink.resolve(raw) else { return }
        let route = AppRoute.from(feedLink: resolved, transitionID: transitionID)
        if case let .web(url) = route, settings.openInBrowser {
            UIApplication.shared.open(url)
            return
        }
        push(route)
    }

    public func openMedia(_ items: [FeedMedia], at index: Int, sourcePrefix: String? = nil) {
        guard !items.isEmpty else { return }
        mediaViewer = MediaViewerPresentation(items: items, initialIndex: index, sourcePrefix: sourcePrefix)
    }

    // MARK: - Error & Captcha Handling

    @discardableResult
    public func handleAPIError(_ error: Error) async -> Bool {
        if error is CancellationError || (error as? APIError).map({
            if case .sessionChanged = $0 { return true }
            return false
        }) == true {
            return false
        }

        if case let APIError.captchaRequired(challenge, _) = error {
            let proof = await requestCaptchaVerification(challenge: challenge)
            if let proof, !proof.isEmpty {
                await CoolapkClient.shared.setCaptchaProof(proof)
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
