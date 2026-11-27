import CoolapkKit
import SwiftUI

public struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var selectedIndex = 0
    @State private var isTesting = false
    @State private var testStatus: String?

    public init() {}

    public var body: some View {
        @Bindable var settings = appState.settings

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("设备标识预设说明", systemImage: "cpu.fill")
                            .font(.headline)
                        Text("首次启动需选择一套固定的设备指纹预设。选择后将持久化保存在本机，确保所有请求与登录态签名保持一致，降低酷安风控拦截概率。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("选择预设机型") {
                    ForEach(Array(DeviceIdentityPreset.catalog.enumerated()), id: \.offset) { index, preset in
                        Button {
                            selectedIndex = index
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(preset.brand) · \(preset.model) (\(preset.buildNumber))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedIndex == index {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .font(.title3)
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("收藏默认保存位置", selection: $settings.defaultFavoriteTarget) {
                        ForEach(SocialStorageTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }

                    Picker("关注默认保存位置", selection: $settings.defaultFollowTarget) {
                        ForEach(SocialStorageTarget.allCases) { target in
                            Text(target.title).tag(target)
                        }
                    }

                    Toggle("读取云端收藏夹列表", isOn: $settings.enableCloudFavoritesLoad)
                    Toggle("读取云端关注列表与关注流", isOn: $settings.enableCloudFollowLoad)
                    Toggle("读取云端浏览历史", isOn: $settings.enableCloudHistoryLoad)
                } header: {
                    Text("收藏、关注与防风控策略")
                } footer: {
                    Text("将收藏与关注默认保存在本机可大幅减少云端高频写操作，有效规避 403 / 图形验证码与账号风控限制。同时支持同名本机与云端收藏夹自动合并展示，后续随时可在「设置」中修改。")
                }

                Section {
                    Button {
                        Task { await applyAndTest() }
                    } label: {
                        HStack {
                            Text("验证连接并进入应用")
                                .font(.headline)
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let testStatus {
                        Text(testStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("作者与关于信息") {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.terminal.on.rectangle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("C001APK (iOS 26 Native)")
                                .font(.subheadline.weight(.semibold))
                            Text("作者：AsrielXuwu · 基于 GNU AGPL v3 开源")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)

                    Button {
                        if let url = URL(string: "mailto:asrielxuwu@outlook.com") {
                            openURL(url)
                        }
                    } label: {
                        LabeledContent("联系邮箱", value: "asrielxuwu@outlook.com")
                    }

                    Button {
                        if let url = URL(string: "https://t.me/swift_c001apk") {
                            openURL(url)
                        }
                    } label: {
                        LabeledContent("Telegram 讨论组", value: "t.me/swift_c001apk")
                    }

                    Button {
                        if let url = URL(string: "https://github.com/AsrielXuwu/swift-c001apk") {
                            openURL(url)
                        }
                    } label: {
                        LabeledContent("项目开源仓库", value: "AsrielXuwu/swift-c001apk")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("致谢开源项目")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("TG-Twilight/c001apk · frisk1127/c001apk-Revived · Mora-han/coolapk-for-mac · bggRGjQaUbCoE/c001apk-flutter")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("欢迎使用 C001APK")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func applyAndTest() async {
        isTesting = true
        testStatus = "正在应用设备指纹并请求首页配置…"
        let preset = DeviceIdentityPreset.catalog[selectedIndex]
        await appState.applyDevicePreset(preset)
        do {
            _ = try await API.homeInit()
            testStatus = "验证成功！"
            appState.completeOnboarding()
        } catch {
            testStatus = "网络请求提示：\(error.localizedDescription)（已保存预设，正在进入应用）"
            try? await Task.sleep(for: .milliseconds(600))
            appState.completeOnboarding()
        }
        isTesting = false
    }
}
