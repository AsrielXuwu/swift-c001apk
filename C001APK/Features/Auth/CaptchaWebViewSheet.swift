import CoolapkKit
import os
import SwiftUI
import UIKit
import WebKit

public struct CaptchaWebViewSheet: View {
    public let challenge: CaptchaChallenge
    public let onComplete: (String?) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var reloadTrigger = 0
    @State private var showHelp = false

    public init(challenge: CaptchaChallenge, onComplete: @escaping (String?) -> Void) {
        self.challenge = challenge
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            CaptchaWebViewRepresentable(
                captchaID: challenge.captchaID,
                reloadTrigger: reloadTrigger
            ) { token in
                onComplete(token)
                dismiss()
            }
            .navigationTitle("人机验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        onComplete(nil)
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    Button {
                        reloadTrigger += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .alert("反复出现人机验证？", isPresented: $showHelp) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("可在“我的 → 设置 → 协议与设备 → 设备标识”里主动获取数盟 ID，或从官方酷安同一页面点击“复制 OAID”5次后粘贴完整内容手动导入。")
            }
        }
    }
}

private struct CaptchaWebViewRepresentable: UIViewRepresentable {
    let captchaID: String
    let reloadTrigger: Int
    let onVerified: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVerified: onVerified)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "captchaVerified")
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.lastReload = reloadTrigger
        webView.loadHTMLString(htmlContent, baseURL: URL(string: "https://www.coolapk.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastReload != reloadTrigger {
            context.coordinator.lastReload = reloadTrigger
            uiView.loadHTMLString(htmlContent, baseURL: URL(string: "https://www.coolapk.com"))
        }
    }

    private var htmlContent: String {
        """
        <!doctype html><html lang="zh-CN"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>:root{color-scheme:light dark}body{font:16px -apple-system,sans-serif;margin:24px;color:CanvasText;background:Canvas}#captcha{margin-top:24px}p{line-height:1.6}</style>
        </head><body><p id="status">正在加载验证组件…</p><div id="captcha"></div>
        <script>
        function statusText(text){document.getElementById('status').textContent=text;}
        (function(){
          var timeout=setTimeout(function(){statusText('验证组件加载超时，请点击右上角刷新');},15000);
          var script=document.createElement('script');
          script.src='https://cstaticdun.126.net/load.min.js';
          script.onerror=function(){clearTimeout(timeout);statusText('验证组件加载失败，请检查网络后刷新');};
          script.onload=function(){
            if(typeof initNECaptcha!=='function'){clearTimeout(timeout);statusText('验证组件不可用');return;}
            initNECaptcha({
              captchaId:'\(captchaID)',
              element:'#captcha',
              protocol:'https',
              mode:'embed',
              apiVersion:2,
              width:Math.min(320,window.innerWidth-48)+'px',
              lang:'zh-CN',
              onVerify:function(err,data){
                if(!err && data && data.validate){
                  window.webkit.messageHandlers.captchaVerified.postMessage(data.validate);
                } else {
                  statusText('验证未通过，请按提示重试');
                }
              }
            },function(){clearTimeout(timeout);statusText('请按下方提示完成人机验证');},
              function(){clearTimeout(timeout);statusText('无法初始化验证，请检查网络后刷新');});
          };
          document.head.appendChild(script);
        })();
        </script></body></html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onVerified: @MainActor @Sendable (String) -> Void
        var lastReload = 0
        private let sentLock = OSAllocatedUnfairLock(initialState: false)

        init(onVerified: @escaping @MainActor @Sendable (String) -> Void) {
            self.onVerified = onVerified
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "captchaVerified", let token = message.body as? String, !token.isEmpty else {
                return
            }
            let shouldSend = sentLock.withLock { sent -> Bool in
                guard !sent else { return false }
                sent = true
                return true
            }
            guard shouldSend else { return }
            Task { @MainActor in
                onVerified(token)
            }
        }
    }
}
