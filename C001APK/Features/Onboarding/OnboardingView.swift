import CoolapkKit
import SwiftUI

public struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var enableFilter = false
    @State private var filterLevel: FilterLevel = .standard
    @State private var hidePublish = false
    @State private var isAcquiringID = false
    @State private var szlmStatus: String?

    public init() {}

    public var body: some View {
        @Bindable var settings = appState.settings

        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("欢迎使用 c001apk")
                            .font(.title2.weight(.bold))
                        Text("原生 iOS 26 SwiftUI 轻量酷安客户端。可随时在“我的 → 设置”里调整下列偏好。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("浏览偏好") {
                    Toggle("开启“屏蔽傻逼内容”本机过滤", isOn: $enableFilter)
                    if enableFilter {
                        Picker("过滤强度", selection: $filterLevel) {
                            ForEach(FilterLevel.allCases, id: \.self) { level in
                                Text(level.label).tag(level)
                            }
                        }
                    }
                    Toggle("不写东西（隐藏主页发布按钮）", isOn: $hidePublish)
                }

                Section {
                    Picker("默认收藏保存位置", selection: $settings.defaultFavoriteTarget) {
                        ForEach(FavoriteStorageMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Picker("默认关注保存位置", selection: $settings.defaultFollowTarget) {
                        ForEach(FollowStorageMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    Toggle("加载云端收藏夹列表", isOn: $settings.enableCloudFavoritesLoad)
                    Toggle("加载云端关注列表与动态", isOn: $settings.enableCloudFollowLoad)
                    Toggle("加载云端浏览历史", isOn: $settings.enableCloudHistoryLoad)
                } header: {
                    Text("收藏、关注与防风控策略")
                } footer: {
                    Text("默认使用本机收藏与本机关注可避免向酷安服务器发送高频写操作，大幅降低触发 403、图形验证码或账号风控限制的概率。同名本机与云端收藏夹会自动合并显示。")
                }

                Section {
                    Button {
                        Task { await acquireIdentity() }
                    } label: {
                        HStack {
                            Text("随机机型参数并获取数盟设备标识")
                            Spacer()
                            if isAcquiringID { ProgressView() }
                        }
                    }
                    .disabled(isAcquiringID)

                    let params = appState.settings.protocolParameters
                    Text("当前机型：\(params.deviceBrand) \(params.deviceModel) · SDK \(params.sdkInt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !params.szlmID.isEmpty {
                        Text("已保存设备标识：\(params.szlmID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(2)
                    } else if let szlmStatus {
                        Text(szlmStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("设备标识与协议防风控")
                } footer: {
                    Text("点击后会自动随机生成并保存一套机型协议参数，然后向数盟服务获取设备标识以减少风控与人机验证；内置默认机型参数仍会保留，可随时在「设置 → 客户端协议参数」重置恢复。")
                }

                Section("作者与关于信息") {
                    LabeledContent("作者", value: "AsrielXuwu")

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
                        LabeledContent("Telegram 群组", value: "t.me/swift_c001apk")
                    }

                    Button {
                        if let url = URL(string: "https://github.com/AsrielXuwu/swift-c001apk") {
                            openURL(url)
                        }
                    } label: {
                        LabeledContent("项目开源仓库", value: "AsrielXuwu/swift-c001apk")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("开源致谢与协议")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("致谢 TG-Twilight/c001apk、frisk1127/c001apk-Revived、Mora-han/coolapk-for-mac、bggRGjQaUbCoE/c001apk-flutter · 本项目遵循 GNU AGPL v3 开源协议，仅供个人学习与研究使用。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("初始设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("开始使用") {
                        appState.contentFilter.enabled = enableFilter
                        appState.contentFilter.level = filterLevel
                        appState.settings.hideHomePublishButton = hidePublish
                        dismiss()
                        Task { @MainActor in
                            await appState.settings.syncProtocolToClient()
                            if appState.settings.autoAcquireSzlmOnLaunch,
                               appState.settings.protocolParameters.szlmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                _ = try? await appState.settings.acquireSzlmID()
                            }
                            await appState.refreshLoginAndBadge()
                            appState.settings.onboardingCompleted = true
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func acquireIdentity() async {
        isAcquiringID = true
        defer { isAcquiringID = false }
        do {
            let id = try await appState.settings.acquireSzlmID(
                forceBypassCooldown: true,
                randomizeDeviceFirst: true
            )
            szlmStatus = "已保存设备标识：\(id)"
        } catch {
            szlmStatus = "获取失败：\(error.localizedDescription)"
        }
    }
}
