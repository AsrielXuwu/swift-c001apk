import CoolapkKit
import SwiftUI

public struct ProtocolParamsView: View {
    @Environment(AppState.self) private var appState
    @State private var draft = ProtocolParameters()
    @State private var hasLoadedInitialDraft = false

    public init() {}

    public var body: some View {
        Form {
            Section("客户端版本标识") {
                LabeledContent("Version Name") {
                    TextField("16.2.0", text: $draft.appVersion)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("App Code") {
                    TextField("2604201", text: $draft.appCode)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("API Version") {
                    TextField("16", text: $draft.apiVersion)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("SDK Int") {
                    TextField("35", text: $draft.sdkInt)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("模拟设备参数") {
                LabeledContent("Brand") {
                    TextField("Xiaomi", text: $draft.deviceBrand)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Model") {
                    TextField("M2102J2SC", text: $draft.deviceModel)
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("User-Agent").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.userAgent)
                        .font(.caption.monospaced())
                        .frame(minHeight: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("X-App-Device").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $draft.deviceCode)
                        .font(.caption.monospaced())
                        .frame(minHeight: 60)
                    Button("重新随机生成 X-App-Device") {
                        let sdk = Int(draft.sdkInt) ?? 35
                        let build = CoolapkToken.buildID(forSDKInt: sdk)
                        draft.deviceCode = CoolapkToken.makeDeviceCode(
                            brand: draft.deviceBrand,
                            model: draft.deviceModel,
                            build: build,
                            identifier: draft.szlmID.isEmpty ? nil : draft.szlmID
                        )
                    }
                }
            }

            Section {
                Button("随机拼接机型与参数") {
                    let preset = CoolapkToken.randomDevicePreset(
                        appVersion: draft.appVersion,
                        appCode: draft.appCode,
                        identifier: draft.szlmID.isEmpty ? nil : draft.szlmID
                    )
                    draft.deviceBrand = preset.brand
                    draft.deviceModel = preset.model
                    draft.sdkInt = preset.sdkInt
                    draft.userAgent = preset.userAgent
                    draft.deviceCode = preset.deviceCode
                    appState.showToast("已随机生成 \(preset.brand) \(preset.model) 参数")
                }

                Button("保存协议参数") {
                    let normalized = draft.normalized()
                    draft = normalized
                    appState.settings.protocolParameters = normalized
                    Task {
                        await appState.settings.syncProtocolToClient()
                        appState.showToast("已保存协议参数")
                    }
                }
                .fontWeight(.semibold)

                Button("恢复默认参数（保留设备标识）", role: .destructive) {
                    draft = appState.settings.resetDeviceParametersToDefault(preserveSzlmID: true)
                    Task {
                        await appState.settings.syncProtocolToClient()
                        appState.showToast("已恢复内置默认机型参数")
                    }
                }
            }
        }
        .navigationTitle("协议参数")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.appVersion) { _, _ in syncDerivedUserAgent() }
        .onChange(of: draft.appCode) { _, _ in syncDerivedUserAgent() }
        .onChange(of: draft.sdkInt) { _, _ in syncDerivedUserAgent() }
        .onChange(of: draft.deviceBrand) { _, _ in syncDerivedUserAgent() }
        .onChange(of: draft.deviceModel) { _, _ in syncDerivedUserAgent() }
        .onAppear {
            draft = appState.settings.protocolParameters
            Task { @MainActor in
                hasLoadedInitialDraft = true
            }
        }
    }

    private func syncDerivedUserAgent() {
        guard hasLoadedInitialDraft else { return }
        draft.userAgent = CoolapkToken.defaultUserAgent(
            deviceBrand: draft.deviceBrand,
            deviceModel: draft.deviceModel,
            appVersion: draft.appVersion,
            appCode: draft.appCode,
            sdkInt: draft.sdkInt
        )
    }
}
