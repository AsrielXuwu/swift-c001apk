import CoolapkKit
import Foundation
import Observation
import SwiftUI

public enum AppearanceMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case system = 0
    case light = 1
    case dark = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "始终浅色"
        case .dark: return "始终深色"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public enum SplitReadingMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = 0
    case alwaysOn = 1
    case alwaysOff = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .automatic: return "自动"
        case .alwaysOn: return "开启"
        case .alwaysOff: return "关闭"
        }
    }
}

public enum MediaAutoLoadMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case always = 0
    case wifiOnly = 1
    case never = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .always: return "始终自动加载"
        case .wifiOnly: return "仅 Wi-Fi"
        case .never: return "手动加载"
        }
    }
}

public enum MediaDisplayStyle: Int, CaseIterable, Codable, Identifiable, Sendable {
    case stackedCards = 0
    case grid = 1

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .stackedCards: return "堆叠卡片 (iMessage)"
        case .grid: return "传统九宫格"
        }
    }
}

public enum FavoriteStorageMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case local = 0
    case cloud = 1

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .local: return "本机收藏（防风控推荐）"
        case .cloud: return "同步至云端收藏夹"
        }
    }
}

public struct BrandPreset: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let color: Color

    public static let presets: [BrandPreset] = [
        BrandPreset(id: 0, name: "酷安绿", color: Color(red: 0.059, green: 0.722, blue: 0.376)),
        BrandPreset(id: 1, name: "系统蓝", color: .blue),
        BrandPreset(id: 2, name: "靛紫", color: .indigo),
        BrandPreset(id: 3, name: "青碧", color: .teal),
        BrandPreset(id: 4, name: "橙琥珀", color: .orange),
        BrandPreset(id: 5, name: "樱桃粉", color: .pink),
        BrandPreset(id: 6, name: "绯红", color: .red)
    ]
}

@MainActor
@Observable
public final class SettingsStore {
    private let defaults = UserDefaults.standard

    public var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: "settings.appearanceMode") }
    }
    public var brandPresetIndex: Int {
        didSet { defaults.set(brandPresetIndex, forKey: "settings.brandPresetIndex") }
    }
    public var homeTabConfig: HomeTabConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(homeTabConfig) {
                defaults.set(data, forKey: "settings.homeTabConfig")
            }
        }
    }
    public var hideHomePublishButton: Bool {
        didSet { defaults.set(hideHomePublishButton, forKey: "settings.hideHomePublishButton") }
    }
    public var splitReadingMode: SplitReadingMode {
        didSet { defaults.set(splitReadingMode.rawValue, forKey: "settings.splitReadingMode") }
    }
    public var fontScale: Double {
        didSet { defaults.set(fontScale, forKey: "settings.fontScale") }
    }
    public var showEmoji: Bool {
        didSet { defaults.set(showEmoji, forKey: "settings.showEmoji") }
    }
    public var foldCoinReplies: Bool {
        didSet { defaults.set(foldCoinReplies, forKey: "settings.foldCoinReplies") }
    }
    public var mediaAutoLoadMode: MediaAutoLoadMode {
        didSet { defaults.set(mediaAutoLoadMode.rawValue, forKey: "settings.mediaAutoLoadMode") }
    }
    public var mediaDisplayStyle: MediaDisplayStyle {
        didSet { defaults.set(mediaDisplayStyle.rawValue, forKey: "settings.mediaDisplayStyle") }
    }
    public var disableHDR: Bool {
        didSet { defaults.set(disableHDR, forKey: "settings.disableHDR") }
    }
    public var livePhotoAutoPlay: Bool {
        didSet { defaults.set(livePhotoAutoPlay, forKey: "settings.livePhotoAutoPlay") }
    }
    public var recordHistory: Bool {
        didSet { defaults.set(recordHistory, forKey: "settings.recordHistory") }
    }
    public var openInBrowser: Bool {
        didSet { defaults.set(openInBrowser, forKey: "settings.openInBrowser") }
    }
    public var autoCheckUpdate: Bool {
        didSet { defaults.set(autoCheckUpdate, forKey: "settings.autoCheckUpdate") }
    }
    public var defaultFavoriteTarget: FavoriteStorageMode {
        didSet { defaults.set(defaultFavoriteTarget.rawValue, forKey: "settings.defaultFavoriteTarget") }
    }
    public var enableCloudFavoritesLoad: Bool {
        didSet { defaults.set(enableCloudFavoritesLoad, forKey: "settings.enableCloudFavoritesLoad") }
    }
    public var enableCloudFollowLoad: Bool {
        didSet { defaults.set(enableCloudFollowLoad, forKey: "settings.enableCloudFollowLoad") }
    }
    public var enableCloudHistoryLoad: Bool {
        didSet { defaults.set(enableCloudHistoryLoad, forKey: "settings.enableCloudHistoryLoad") }
    }
    public var autoAcquireSzlmOnLaunch: Bool {
        didSet { defaults.set(autoAcquireSzlmOnLaunch, forKey: "settings.autoAcquireSzlmOnLaunch") }
    }
    public var enableHapticFeedback: Bool {
        didSet { defaults.set(enableHapticFeedback, forKey: "settings.enableHapticFeedback") }
    }
    public var livePhotoLoopPlay: Bool {
        didSet { defaults.set(livePhotoLoopPlay, forKey: "settings.livePhotoLoopPlay") }
    }
    public var useOledPureBlackDarkMode: Bool {
        didSet { defaults.set(useOledPureBlackDarkMode, forKey: "settings.useOledPureBlackDarkMode") }
    }
    public var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: "settings.onboardingCompleted") }
    }
    public var searchHistory: [String] {
        didSet { defaults.set(searchHistory, forKey: "settings.searchHistory") }
    }
    public var protocolParameters: ProtocolParameters {
        didSet {
            if let data = try? JSONEncoder().encode(protocolParameters) {
                defaults.set(data, forKey: "settings.protocolParameters")
            }
            Task {
                await CoolapkClient.shared.updateParameters(protocolParameters)
                await ImagePipeline.shared.updateUserAgent(protocolParameters.userAgent)
            }
        }
    }

    public var szlmLastAcquiredAt: Date? {
        didSet { defaults.set(szlmLastAcquiredAt?.timeIntervalSince1970, forKey: "settings.szlmLastAcquiredAt") }
    }
    public var szlmAcquisitionAttempts: [Date] {
        didSet { defaults.set(szlmAcquisitionAttempts.map(\.timeIntervalSince1970), forKey: "settings.szlmAcquisitionAttempts") }
    }
    public var ignoreSzlmCooldown: Bool {
        didSet { defaults.set(ignoreSzlmCooldown, forKey: "settings.ignoreSzlmCooldown") }
    }

    public var accentColor: Color {
        BrandPreset.presets.first { $0.id == brandPresetIndex }?.color ?? BrandPreset.presets[0].color
    }

    public init() {
        self.appearanceMode = AppearanceMode(rawValue: defaults.integer(forKey: "settings.appearanceMode")) ?? .system
        self.brandPresetIndex = defaults.integer(forKey: "settings.brandPresetIndex")

        if let tabData = defaults.data(forKey: "settings.homeTabConfig"),
           let decodedTabs = try? JSONDecoder().decode(HomeTabConfiguration.self, from: tabData) {
            self.homeTabConfig = decodedTabs
        } else {
            self.homeTabConfig = HomeTabConfiguration()
        }

        self.hideHomePublishButton = defaults.bool(forKey: "settings.hideHomePublishButton")
        self.splitReadingMode = SplitReadingMode(rawValue: defaults.integer(forKey: "settings.splitReadingMode")) ?? .automatic
        let savedScale = defaults.double(forKey: "settings.fontScale")
        self.fontScale = savedScale > 0 ? savedScale : 1.0

        self.showEmoji = defaults.object(forKey: "settings.showEmoji") as? Bool ?? true
        self.foldCoinReplies = defaults.bool(forKey: "settings.foldCoinReplies")
        self.mediaAutoLoadMode = MediaAutoLoadMode(rawValue: defaults.integer(forKey: "settings.mediaAutoLoadMode")) ?? .always
        self.mediaDisplayStyle = MediaDisplayStyle(rawValue: defaults.integer(forKey: "settings.mediaDisplayStyle")) ?? .stackedCards
        self.disableHDR = defaults.bool(forKey: "settings.disableHDR")
        self.livePhotoAutoPlay = defaults.object(forKey: "settings.livePhotoAutoPlay") as? Bool ?? true
        self.recordHistory = defaults.object(forKey: "settings.recordHistory") as? Bool ?? true
        self.openInBrowser = defaults.bool(forKey: "settings.openInBrowser")
        self.autoCheckUpdate = defaults.object(forKey: "settings.autoCheckUpdate") as? Bool ?? true
        self.defaultFavoriteTarget = FavoriteStorageMode(rawValue: defaults.integer(forKey: "settings.defaultFavoriteTarget")) ?? .local
        self.enableCloudFavoritesLoad = defaults.object(forKey: "settings.enableCloudFavoritesLoad") as? Bool ?? true
        self.enableCloudFollowLoad = defaults.object(forKey: "settings.enableCloudFollowLoad") as? Bool ?? true
        self.enableCloudHistoryLoad = defaults.object(forKey: "settings.enableCloudHistoryLoad") as? Bool ?? true
        self.autoAcquireSzlmOnLaunch = defaults.object(forKey: "settings.autoAcquireSzlmOnLaunch") as? Bool ?? true
        self.enableHapticFeedback = defaults.object(forKey: "settings.enableHapticFeedback") as? Bool ?? true
        self.livePhotoLoopPlay = defaults.bool(forKey: "settings.livePhotoLoopPlay")
        self.useOledPureBlackDarkMode = defaults.bool(forKey: "settings.useOledPureBlackDarkMode")
        self.onboardingCompleted = defaults.bool(forKey: "settings.onboardingCompleted")
        self.searchHistory = defaults.stringArray(forKey: "settings.searchHistory") ?? []

        if let protoData = defaults.data(forKey: "settings.protocolParameters"),
           let decodedProto = try? JSONDecoder().decode(ProtocolParameters.self, from: protoData) {
            self.protocolParameters = decodedProto
        } else {
            let initial = ProtocolParameters()
            if let encoded = try? JSONEncoder().encode(initial) {
                defaults.set(encoded, forKey: "settings.protocolParameters")
            }
            self.protocolParameters = initial
        }

        if let ts = defaults.object(forKey: "settings.szlmLastAcquiredAt") as? TimeInterval {
            self.szlmLastAcquiredAt = Date(timeIntervalSince1970: ts)
        } else {
            self.szlmLastAcquiredAt = nil
        }
        let attemptTimes = defaults.array(forKey: "settings.szlmAcquisitionAttempts") as? [TimeInterval] ?? []
        self.szlmAcquisitionAttempts = attemptTimes.map(Date.init(timeIntervalSince1970:))
        self.ignoreSzlmCooldown = defaults.bool(forKey: "settings.ignoreSzlmCooldown")
    }

    public func syncProtocolToClient() async {
        await CoolapkClient.shared.updateParameters(protocolParameters)
        await ImagePipeline.shared.updateUserAgent(protocolParameters.userAgent)
    }

    public func addSearchHistory(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchHistory.removeAll { $0 == trimmed }
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > 20 { searchHistory = Array(searchHistory.prefix(20)) }
    }

    public func removeSearchHistory(_ keyword: String) {
        searchHistory.removeAll { $0 == keyword }
    }

    public func clearSearchHistory() {
        searchHistory.removeAll()
    }

    // MARK: - SZLM Acquisition Rate Limiter

    public var szlmNextAllowedAt: Date? {
        guard !ignoreSzlmCooldown else { return nil }
        let now = Date()
        let threshold = now.addingTimeInterval(-86400)
        let recent = szlmAcquisitionAttempts.filter { $0 > threshold }.sorted()
        var candidates: [Date] = []
        if let lastSuccess = szlmLastAcquiredAt {
            candidates.append(lastSuccess.addingTimeInterval(7 * 86400))
        }
        if let lastAttempt = recent.last {
            candidates.append(lastAttempt.addingTimeInterval(5 * 60))
        }
        if recent.count >= 3 {
            candidates.append(recent[recent.count - 3].addingTimeInterval(86400))
        }
        return candidates.filter { $0 > now }.max()
    }

    @discardableResult
    public func randomizeDeviceParameters() -> ProtocolParameters {
        var updated = protocolParameters
        let preset = CoolapkToken.randomDevicePreset(
            appVersion: updated.appVersion,
            appCode: updated.appCode
        )
        updated.deviceBrand = preset.brand
        updated.deviceModel = preset.model
        updated.sdkInt = preset.sdkInt
        updated.userAgent = preset.userAgent
        updated.deviceCode = preset.deviceCode
        protocolParameters = updated
        return updated
    }

    public func acquireSzlmID(
        forceBypassCooldown: Bool = false,
        randomizeDeviceFirst: Bool = false
    ) async throws -> String {
        if !forceBypassCooldown, let next = szlmNextAllowedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            throw SzlmDuidError("可再次获取时间：\(formatter.string(from: next))")
        }
        if randomizeDeviceFirst {
            _ = randomizeDeviceParameters()
        }
        let now = Date()
        let threshold = now.addingTimeInterval(-86400)
        szlmAcquisitionAttempts = szlmAcquisitionAttempts.filter { $0 > threshold } + [now]
        let sdk = Int(protocolParameters.sdkInt) ?? 35
        let androidVer = CoolapkToken.androidVersion(forSDKInt: sdk)
        let acquired = try await SzlmDuidClient.acquire(
            manufacturer: protocolParameters.deviceBrand,
            model: protocolParameters.deviceModel,
            androidVersion: androidVer,
            sdkInt: sdk
        )
        szlmLastAcquiredAt = Date()
        var updated = protocolParameters
        updated.szlmID = acquired
        protocolParameters = updated
        await CoolapkClient.shared.updateParameters(updated)
        await CoolapkClient.shared.clearCaptchaState()
        return acquired
    }
}
