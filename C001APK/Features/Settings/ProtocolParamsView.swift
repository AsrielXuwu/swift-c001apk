import CoolapkKit
import SwiftUI

public struct ProtocolParamsView: View {
    @Environment(AppState.self) private var appState
    @State private var draft = ProtocolParameters()

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
                        draft.deviceCode = CoolapkToken.makeDeviceCode(
                            brand: draft.deviceBrand,
                            model: draft.deviceModel
                        )
                    }
                }
            }

            Section {
                Button("随机拼接机型与参数") {
                    let preset = CoolapkToken.randomDevicePreset(
                        appVersion: draft.appVersion,
                        appCode: draft.appCode
                    )
                    draft.deviceBrand = preset.brand
                    draft.deviceModel = preset.model
                    draft.sdkInt = preset.sdkInt
                    draft.userAgent = preset.userAgent
                    draft.deviceCode = preset.deviceCode
                    appState.showToast("已随机生成 \(preset.brand) \(preset.model) 参数")
                }

                Button("保存协议参数") {
                    appState.settings.protocolParameters = draft
                    appState.showToast("已保存协议参数")
                }
                .fontWeight(.semibold)

                Button("恢复默认参数", role: .destructive) {
                    draft = ProtocolParameters()
                    appState.settings.protocolParameters = draft
                    appState.showToast("已恢复默认参数")
                }
            }
        }
        .navigationTitle("协议参数")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draft = appState.settings.protocolParameters
        }
    }
}
