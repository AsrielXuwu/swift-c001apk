import SwiftUI

public struct AboutView: View {
    public init() {}

    private var appVersion: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(ver) (\(build))"
    }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                    Text("c001apk for iOS")
                        .font(.title2.weight(.bold))
                    Text("版本 \(appVersion) · iOS 27 原生 SwiftUI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("作者与交流") {
                LabeledContent("作者", value: "AsrielXuwu")
                Link(destination: URL(string: "mailto:asrielxuwu@outlook.com")!) {
                    LabeledContent("邮箱", value: "asrielxuwu@outlook.com")
                }
                Link(destination: URL(string: "https://t.me/swift_c001apk")!) {
                    LabeledContent("Telegram 群组", value: "t.me/swift_c001apk")
                }
                Link("GitHub 仓库 (AsrielXuwu/swift-c001apk)", destination: URL(string: "https://github.com/AsrielXuwu/swift-c001apk")!)
            }

            Section("项目与致谢") {
                Link("TG-Twilight/c001apk (功能原仓库)", destination: URL(string: "https://github.com/TG-Twilight/c001apk")!)
                Link("frisk1127/c001apk-Revived (协议与功能参考)", destination: URL(string: "https://github.com/frisk1127/c001apk-Revived")!)
                Link("Mora-han/coolapk-for-mac (Swift 协议参考)", destination: URL(string: "https://github.com/Mora-han/coolapk-for-mac")!)
                Link("bggRGjQaUbCoE/c001apk-flutter (上游项目)", destination: URL(string: "https://github.com/bggRGjQaUbCoE/c001apk-flutter")!)
            }

            Section {
                Text("本应用为非官方开源酷安第三方客户端，基于 GNU AGPL v3 协议理念移植，与酷安官方无隶属关系。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
