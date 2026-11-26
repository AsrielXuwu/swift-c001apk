import CoolapkKit
import SwiftUI

public struct ContentFilterGateView: View {
    public let reason: String
    public let onRevealTemporarily: () -> Void
    public let onAllowAuthor: (() -> Void)?

    public init(reason: String, onRevealTemporarily: @escaping () -> Void, onAllowAuthor: (() -> Void)? = nil) {
        self.reason = reason
        self.onRevealTemporarily = onRevealTemporarily
        self.onAllowAuthor = onAllowAuthor
    }

    public var body: some View {
        ContentUnavailableView {
            Label("已按本机屏蔽规则隐藏", systemImage: "eye.slash")
        } description: {
            Text("命中原因：\(reason)\n该屏蔽仅在本机生效，未对账号执行拉黑或举报。")
        } actions: {
            Button("临时查看本次内容") {
                onRevealTemporarily()
            }
            .buttonStyle(.borderedProminent)

            if let onAllowAuthor {
                Button("始终允许此作者") {
                    onAllowAuthor()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
