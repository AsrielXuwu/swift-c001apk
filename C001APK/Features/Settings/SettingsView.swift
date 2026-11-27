import CoolapkKit
import SwiftUI
import UIKit

public struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var cacheBytes: Int64 = 0
    @State private var showClearCacheDialog = false
    @State private var showTabEditor = false
    @State private var isCheckingUpdate = false
    @State private var latestRelease: AppReleaseInfo?
    @State private var showReleaseAlert = false

    public init() {}

    public var body: some View {
        @Bindable var settings = appState.settings
        @Bindable var localFollow = appState.localFollow

        Form {
            Section("外观与导航") {
                Picker("主题颜色", selection: $settings.brandPresetIndex) {
                    ForEach(BrandPreset.presets) { preset in
                        HStack {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 14, height: 14)
                            Text(preset.name)
                        }
                        .tag(preset.id)
                    }
                }

                Picker("深色模式", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("OLED 纯黑深色背景", isOn: $settings.useOledPureBlackDarkMode)

                Button("编辑主页分类顺序与显隐") {
                    showTabEditor = true
                }

                Toggle("不写东西（隐藏主页发布按钮）", isOn: $settings.hideHomePublishButton)
                Toggle("触感反馈", isOn: $settings.enableHapticFeedback)
            }

            Section("阅读与评论") {
                Picker("分栏阅读", selection: $settings.splitReadingMode) {
                    ForEach(SplitReadingMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("阅读字号倍率")
                        Spacer()
                        Text(String(format: "%.2fx", settings.fontScale))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.fontScale, in: 0.85...1.35, step: 0.05)
                }

                Toggle("显示酷安表情", isOn: $settings.showEmoji)
                Toggle("自动折叠酷币表情评论", isOn: $settings.foldCoinReplies)
            }

            Section("图片与媒体") {
                Picker("多图展示样式", selection: $settings.mediaDisplayStyle) {
                    ForEach(MediaDisplayStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Picker("图片加载策略", selection: $settings.mediaAutoLoadMode) {
                    ForEach(MediaAutoLoadMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("实况图片进入大图自动播放一次", isOn: $settings.livePhotoAutoPlay)
                Toggle("实况图片大图默认循环播放", isOn: $settings.livePhotoLoopPlay)
                Toggle("我不想看 HDR", isOn: $settings.disableHDR)
            }

            Section {
                Picker("收藏写入位置", selection: $settings.defaultFavoriteTarget) {
                    ForEach(FavoriteStorageMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("关注写入位置", selection: $settings.defaultFollowTarget) {
                    ForEach(FollowStorageMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("读取云端收藏夹列表", isOn: $settings.enableCloudFavoritesLoad)
                Toggle("读取云端关注列表与关注流", isOn: $settings.enableCloudFollowLoad)
                Toggle("读取云端浏览历史", isOn: $settings.enableCloudHistoryLoad)
                if appState.accounts.isLoggedIn {
                    Toggle("悄悄关注", isOn: $localFollow.secretFollowEnabled)
                }
                NavigationLink(value: AppRoute.localFollowList) {
                    Text("管理关注列表（本机与云端）")
                }
            } header: {
                Text("收藏、关注与防风控")
            } footer: {
                Text("收藏与关注默认仅写入本机（防风控推荐）；登录账号后可在上方切换同步至云端，游客模式仅写入本机。关闭云端读取可最大程度减少风控。")
            }

            Section("内容屏蔽") {
                NavigationLink(value: AppRoute.contentFilterSettings) {
                    HStack {
                        Text("屏蔽傻逼内容")
                        Spacer()
                        Text(appState.contentFilter.enabled ? appState.contentFilter.level.label : "已关闭")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink(value: AppRoute.blacklist(isTopic: false)) {
                    HStack {
                        Text("用户黑名单")
                        Spacer()
                        Text("\(appState.blacklist.blockedUsers.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink(value: AppRoute.blacklist(isTopic: true)) {
                    HStack {
                        Text("话题黑名单")
                        Spacer()
                        Text("\(appState.blacklist.blockedTopics.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("浏览与隐私") {
                Toggle("记录本机浏览历史", isOn: $settings.recordHistory)
                Toggle("自动读取剪贴板酷安链接跳转", isOn: $settings.autoDetectClipboardLink)
                Toggle("使用系统浏览器打开外部链接", isOn: $settings.openInBrowser)
            }

            Section("存储与更新") {
                Toggle("启动时自动检查版本更新", isOn: $settings.autoCheckUpdate)

                Button {
                    Task { await checkUpdates() }
                } label: {
                    HStack {
                        Text("检查最新 Release")
                        Spacer()
                        if isCheckingUpdate { ProgressView() }
                    }
                }
                .disabled(isCheckingUpdate)

                Picker("自动清理缓存上限", selection: $settings.maxImageCacheMB) {
                    ForEach(SettingsStore.imageCacheLimitOptionsMB, id: \.self) { mb in
                        Text(mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB")
                            .tag(mb)
                    }
                }

                Button(role: .destructive) {
                    showClearCacheDialog = true
                } label: {
                    HStack {
                        Text("清理图片缓存")
                        Spacer()
                        Text(Formatting.byteSize(cacheBytes))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("协议与设备") {
                Toggle("启动时自动获取数盟 DUID", isOn: $settings.autoAcquireSzlmOnLaunch)
                NavigationLink(value: AppRoute.deviceIdentity) {
                    Text("设备标识（数盟 DUID）")
                }
                NavigationLink(value: AppRoute.protocolParams) {
                    Text("客户端协议参数")
                }
            }

            Section {
                Button("重新打开使用引导") {
                    appState.showOnboarding = true
                }
                NavigationLink(value: AppRoute.accounts) {
                    Text("账号管理")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTabEditor) {
            HomeTabsEditorSheet()
        }
        .confirmationDialog("确定清理所有已缓存的图片与离线临时文件？", isPresented: $showClearCacheDialog, titleVisibility: .visible) {
            Button("确认清理", role: .destructive) {
                Task {
                    await ImagePipeline.shared.clearAllCaches()
                    RichTextRenderer.purgeCache()
                    cacheBytes = await ImagePipeline.shared.diskCacheByteCount()
                    appState.showToast("已清理缓存")
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("发现版本 \(latestRelease?.tagName ?? "")", isPresented: $showReleaseAlert) {
            if let url = latestRelease?.htmlURL {
                Button("前往 GitHub 查看") {
                    UIApplication.shared.open(url)
                }
            }
            Button("关闭", role: .cancel) {}
        } message: {
            Text(latestRelease?.name ?? "")
        }
        .task {
            cacheBytes = await ImagePipeline.shared.diskCacheByteCount()
        }
        .onChange(of: settings.maxImageCacheMB) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                cacheBytes = await ImagePipeline.shared.diskCacheByteCount()
            }
        }
    }

    private func checkUpdates() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        do {
            if let release = try await UpdateChecker.fetchLatestRelease() {
                latestRelease = release
                showReleaseAlert = true
            } else {
                appState.showToast("未获取到新版本信息")
            }
        } catch {
            appState.showToast("检查更新失败：\(error.localizedDescription)")
        }
    }
}
