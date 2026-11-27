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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let scheme = url?.scheme?.lowercased() ?? ""
            if !scheme.isEmpty && scheme != "http" && scheme != "https" && scheme != "about" {
                decisionHandler(.cancel)
                return
            }

            let host = url?.host?.lowercased() ?? ""
            let isExternalAppRedirect =
                (!host.isEmpty && !host.contains("coolapk.com") && !host.contains("coolmarket.com") && !host.contains("qq.com") && !host.contains("weibo.com") && !host.contains("alipay.com") && !host.contains("geetest.com"))
                || (url?.absoluteString.contains("openapp") == true)
                || (url?.absoluteString.contains("coolmarket") == true)

            Task { @MainActor [weak self] in
                await self?.captureCookiesIfReady(from: webView)
                if self?.finished == true || isExternalAppRedirect {
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            Task { @MainActor [weak self] in
                await self?.captureCookiesIfReady(from: webView)
                decisionHandler(self?.finished == true ? .cancel : .allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                await self?.captureCookiesIfReady(from: webView)
            }
        }

        private func captureCookiesIfReady(from webView: WKWebView) async {
            guard !finished else { return }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            var map: [String: String] = [:]
            for cookie in cookies where cookie.domain.contains("coolapk.com") {
                map[cookie.name] = cookie.value
            }
            if let uid = map["uid"], !uid.isEmpty,
               let token = map["token"], !token.isEmpty {
                finished = true
                let rawName = map["username"] ?? uid
                let username = rawName.removingPercentEncoding ?? rawName
                let sessid = map["SESSID"] ?? ""
                onCapturedCredentials(uid, username, token, sessid)
            }
        }
    }
}
