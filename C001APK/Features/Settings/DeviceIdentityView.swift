import CoolapkKit
import SwiftUI
import UIKit

public struct DeviceIdentityView: View {
    @Environment(AppState.self) private var appState
    @State private var pasteInput = ""
    @State private var isAcquiring = false

    public init() {}

    public var body: some View {
        let currentID = appState.settings.protocolParameters.szlmID

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
            } footer: {
                Text("不会在启动或回到前台时自动获取设备标识。仅在反复触发人机验证时主动获取或从官方酷安手动导入。")
            }

            Section("自动获取") {
                Button {
                    Task { await acquire() }
                } label: {
                    HStack {
                        Text("立即向数盟获取设备标识")
                        Spacer()
                        if isAcquiring { ProgressView() }
                    }
                }
                .disabled(isAcquiring)

                if let next = appState.settings.szlmNextAllowedAt {
                    Text("冷却至：\(next.formatted(date: .abbreviated, time: .shortened))")
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

    private func acquire() async {
        isAcquiring = true
        defer { isAcquiring = false }
        do {
            _ = try await appState.settings.acquireSzlmID()
            appState.showToast("已获取并保存数盟设备标识")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func importPastedText() {
        do {
            let parsed = try OfficialDeviceIdentity.parse(pasteInput)
            var updated = appState.settings.protocolParameters
            updated.szlmID = parsed
            appState.settings.protocolParameters = updated
            pasteInput = ""
            appState.showToast("已导入并应用 ShuzlmID")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
