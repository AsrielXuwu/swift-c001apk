import CoolapkKit
import SwiftUI
import UIKit

public struct LoginSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var account = ""
    @State private var password = ""
    @State private var captchaText = ""
    @State private var requestHash: String?
    @State private var captchaImage: UIImage?
    @State private var showCaptcha = false
    @State private var isSubmitting = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("手机号 / 邮箱 / 用户名", text: $account)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("密码", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("密码仅用于本次向酷安登录接口提交校验，不会保存到本地。")
                }

                if showCaptcha {
                    Section("图形验证码") {
                        HStack {
                            if let captchaImage {
                                Image(uiImage: captchaImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            } else {
                                ProgressView()
                            }
                            Spacer()
                            Button("换一张") {
                                Task { await loadCaptchaImage() }
                            }
                        }

                        TextField("输入图形验证码", text: $captchaText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section {
                    Button {
                        Task { await submitLogin() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("登录")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting || account.isEmpty || password.isEmpty || requestHash == nil)

                    Button("使用网页登录（推荐触发人机验证时使用）") {
                        dismiss()
                        appState.showWebLoginSheet = true
                    }
                }
            }
            .navigationTitle("登录酷安")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                await prepareLoginSession()
            }
        }
    }

    private func prepareLoginSession() async {
        do {
            requestHash = try await CoolapkClient.shared.fetchLoginRequestHash()
        } catch {
            appState.showToast("无法初始化登录：\(error.localizedDescription)")
        }
    }

    private func loadCaptchaImage() async {
        if let data = try? await CoolapkClient.shared.fetchLoginCaptchaImage(),
           let img = UIImage(data: data) {
            captchaImage = img
            showCaptcha = true
            captchaText = ""
        }
    }

    private func submitLogin() async {
        guard let requestHash else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let result = try await CoolapkClient.shared.loginByCoolapk(
                requestHash: requestHash,
                account: account,
                password: password,
                captcha: captchaText
            )
            if result.status == 1, !result.uid.isEmpty, !result.token.isEmpty {
                try await appState.accounts.saveLogin(
                    uid: result.uid,
                    username: result.username,
                    token: result.token,
                    sessid: result.sessid
                )
                appState.notifyAccountSessionChanged()
                appState.showToast("登录成功")
                dismiss()
                return
            }

            if !result.message.isEmpty {
                appState.showToast(result.message)
            }
            if result.message.contains("图形验证码") || (showCaptcha && result.message.contains("密码")) {
                await loadCaptchaImage()
            } else if result.message.contains("人机") || result.messageStatus == "err_request_captcha_v2" {
                dismiss()
                appState.showWebLoginSheet = true
            }
        } catch {
            appState.showToast("登录失败：\(error.localizedDescription)")
        }
    }
}
