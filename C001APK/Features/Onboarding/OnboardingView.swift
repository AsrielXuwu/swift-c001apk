import CoolapkKit
import SwiftUI

public struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var enableFilter = false
    @State private var filterLevel: FilterLevel = .standard
    @State private var hidePublish = false
    @State private var isAcquiringID = false
    @State private var szlmStatus: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("欢迎使用 c001apk")
                            .font(.title2.weight(.bold))
                        Text("原生 iOS 27 SwiftUI 轻量酷安客户端。可随时在“我的 → 设置”里调整下列偏好。")
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
                } footer: {
                    Text("点击后会自动随机生成并保存一套机型协议参数，然后向数盟服务获取设备标识以减少风控与人机验证；内置默认机型参数仍会保留，可随时在「设置 → 客户端协议参数」重置恢复。")
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
                        appState.settings.onboardingCompleted = true
                        dismiss()
                        Task { @MainActor in
                            await CoolapkClient.shared.updateParameters(appState.settings.protocolParameters)
                            await ImagePipeline.shared.updateUserAgent(appState.settings.protocolParameters.userAgent)
                            await appState.refreshLoginAndBadge()
                            appState.feedRefreshTrigger += 1
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
