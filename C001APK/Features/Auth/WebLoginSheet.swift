import CoolapkKit
import SwiftUI
import UIKit
import WebKit

public struct WebLoginSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            WebLoginRepresentable { uid, username, token, sessid in
                Task {
                    try? await appState.accounts.saveLogin(
                        uid: uid,
                        username: username,
                        token: token,
                        sessid: sessid
                    )
                    appState.notifyAccountSessionChanged()
                    appState.showToast("登录成功")
                    dismiss()
                }
            }
            .navigationTitle("网页登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct WebLoginRepresentable: UIViewRepresentable {
    let onCapturedCredentials: (String, String, String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapturedCredentials: onCapturedCredentials)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        if let url = URL(string: "https://account.coolapk.com/auth/login?type=mobile") {
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCapturedCredentials: (String, String, String, String) -> Void
        private var finished = false

        init(onCapturedCredentials: @escaping (String, String, String, String) -> Void) {
            self.onCapturedCredentials = onCapturedCredentials
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                guard let self, !self.finished else { return }
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                var map: [String: String] = [:]
                for cookie in cookies where cookie.domain.contains("coolapk.com") {
                    map[cookie.name] = cookie.value
                }
                if let uid = map["uid"], !uid.isEmpty,
                   let token = map["token"], !token.isEmpty {
                    self.finished = true
                    let username = map["username"] ?? uid
                    let sessid = map["SESSID"] ?? ""
                    self.onCapturedCredentials(uid, username, token, sessid)
                }
            }
        }
    }
}
