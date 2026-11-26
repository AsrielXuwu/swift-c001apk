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
                            Text("可选：主动获取数盟设备标识")
                            Spacer()
                            if isAcquiringID { ProgressView() }
                        }
                    }
                    .disabled(isAcquiringID)

                    if let szlmStatus {
                        Text(szlmStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("仅在你主动点击时联系数盟服务以减少人机验证；不会在后台或启动时自动取号。")
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
            _ = try await appState.settings.acquireSzlmID()
            szlmStatus = "已获取并应用数盟设备标识"
        } catch {
            szlmStatus = error.localizedDescription
        }
    }
}
