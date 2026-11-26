import CoolapkKit
import SwiftUI

public struct AccountsView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        List {
            Section {
                Button {
                    Task {
                        await appState.accounts.useGuest()
                        appState.notifyAccountSessionChanged()
                        appState.showToast("已切换到游客模式")
                    }
                } label: {
                    HStack {
                        Label("游客模式", systemImage: "person.fill.questionmark")
                        Spacer()
                        if !appState.accounts.isLoggedIn {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            } footer: {
                Text("切换账号或进入游客模式时会自动取消未完成的旧账号请求并清理验证码会话。")
            }

            if !appState.accounts.accounts.isEmpty {
                Section("已保存账号") {
                    ForEach(appState.accounts.accounts) { account in
                        Button {
                            if account.needsRelogin {
                                appState.showLoginSheet = true
                            } else {
                                Task {
                                    do {
                                        try await appState.accounts.switchTo(uid: account.uid)
                                        appState.notifyAccountSessionChanged()
                                        appState.showToast("已切换到 \(account.displayName)")
                                    } catch {
                                        appState.showToast(error.localizedDescription)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(url: account.avatar, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(account.needsRelogin ? "凭证已过期，点击重新登录" : "UID: \(account.uid) · Lv.\(account.level)")
                                        .font(.caption)
                                        .foregroundStyle(account.needsRelogin ? Color.red : Color.secondary)
                                }
                                Spacer()
                                if appState.accounts.activeUID == account.uid && !account.needsRelogin {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .swipeActions {
                            Button("移除", role: .destructive) {
                                Task {
                                    let wasActive = appState.accounts.activeUID == account.uid
                                    await appState.accounts.remove(uid: account.uid)
                                    if wasActive { appState.notifyAccountSessionChanged() }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    appState.showLoginSheet = true
                } label: {
                    Label("添加 / 登录酷安账号", systemImage: "plus.circle")
                }
                Button {
                    appState.showWebLoginSheet = true
                } label: {
                    Label("通过网页登录", systemImage: "globe")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("账号管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}
