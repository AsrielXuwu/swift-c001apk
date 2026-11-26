import CoolapkKit
import SwiftUI
import UIKit

public struct DeviceIdentityView: View {
    @Environment(AppState.self) private var appState
    @State private var pasteInput = ""
    @State private var isAcquiring = false

    public init() {}

    public var body: some View {
        @Bindable var settings = appState.settings
        let currentID = settings.protocolParameters.szlmID

        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前数盟设备标识 (ShuzlmID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currentID.isEmpty ? "未设置" : currentID)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Text("当前模拟机型：\(settings.protocolParameters.deviceBrand) \(settings.protocolParameters.deviceModel) · SDK \(settings.protocolParameters.sdkInt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("当遇到「系统环境存在异常」或频繁人机验证时，可点击下方随机生成新机型参数并强制重新获取数盟标识。")
            }

            Section("自动获取") {
                Button {
                    Task { await acquire(forceBypass: false, randomizeFirst: false) }
                } label: {
                    HStack {
                        Text("立即向数盟获取设备标识")
                        Spacer()
                        if isAcquiring { ProgressView() }
                    }
                }
                .disabled(isAcquiring)

                Button {
                    Task { await acquire(forceBypass: true, randomizeFirst: true) }
                } label: {
                    HStack {
                        Text("随机机型参数并强制获取新标识")
                        Spacer()
                        if isAcquiring { ProgressView() }
                    }
                }
                .disabled(isAcquiring)

                Toggle("无视冷却冻结时间限制", isOn: $settings.ignoreSzlmCooldown)

                if let next = settings.szlmNextAllowedAt {
                    Text("默认冷却至：\(next.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextEditor(text: $pasteInput)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 90)
                Button("解析并应用 ShuzlmID") {
                    importPastedText()
                }
                .disabled(pasteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("从剪贴板粘贴") {
                    if let clip = UIPasteboard.general.string {
                        pasteInput = clip
                    }
                }

                Link("查看官方导入图文说明", destination: OfficialDeviceIdentity.guideURL)
            } header: {
                Text("从官方酷安手动导入")
            } footer: {
                Text("请在官方酷安同一设置页面累计点击“复制 OAID”5 次后，将完整复制文本粘贴到上方。")
            }
        }
        .navigationTitle("设备标识")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func acquire(forceBypass: Bool, randomizeFirst: Bool) async {
        isAcquiring = true
        defer { isAcquiring = false }
        do {
            _ = try await appState.settings.acquireSzlmID(
                forceBypassCooldown: forceBypass,
                randomizeDeviceFirst: randomizeFirst
            )
            appState.showToast(randomizeFirst ? "已随机机型并更新数盟设备标识" : "已获取并保存数盟设备标识")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func importPastedText() {
        do {
            let parsed = try OfficialDeviceIdentity.parse(pasteInput)
            pasteInput = ""
            Task {
                await appState.settings.applyManualSzlmID(parsed)
                appState.showToast("已导入并应用 ShuzlmID")
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
