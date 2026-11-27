import CoolapkKit
import SwiftUI

public struct ProfileTabView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        List {
            Section {
                if let active = appState.accounts.activeAccount {
                    Button {
                        appState.push(.user(
                            uid: active.uid,
                            initialUsername: appState.currentUserProfile?.username ?? active.displayName,
                            initialAvatar: appState.currentUserProfile?.avatar ?? active.avatar
                        ))
                    } label: {
                        HStack(spacing: 14) {
                            AvatarView(url: appState.currentUserProfile?.avatar ?? active.avatar, size: 58)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(appState.currentUserProfile?.username ?? active.displayName)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Lv.\(appState.currentUserProfile?.level ?? active.level)")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text("UID: \(active.uid)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let profile = appState.currentUserProfile {
                                    Text("\(Formatting.count(profile.feedNum)) 动态 · \(Formatting.count(profile.followNum)) 关注 · \(Formatting.count(profile.fansNum)) 粉丝")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("游客模式")
                                .font(.title3.weight(.semibold))
                            Text("可正常浏览信息流、本地收藏与本地关注")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("登录") {
                            appState.showLoginSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                NavigationLink(value: AppRoute.accounts) {
                    Label {
                        HStack {
                            Text("账号管理")
                            Spacer()
                            Text("已保存 \(appState.accounts.accounts.count) 个")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.2.badge.key")
                    }
                }
                NavigationLink(value: AppRoute.about) {
                    Label("关于 c001apk", systemImage: "info.circle")
                }
            }

            Section("我的内容") {
                NavigationLink(value: AppRoute.favorites) {
                    Label("收藏", systemImage: "star")
                }
                NavigationLink(value: AppRoute.history) {
                    Label("浏览历史", systemImage: "clock")
                }
                NavigationLink(value: AppRoute.localFollowList) {
                    Label(appState.accounts.isLoggedIn ? "悄悄关注" : "本机关注", systemImage: "person.badge.shield.checkmark")
                }
                NavigationLink(value: AppRoute.myRecentVisits) {
                    Label("我的常去", systemImage: "location")
                }
                NavigationLink(value: AppRoute.myLikes) {
                    Label("我的赞", systemImage: "hand.thumbsup")
                }
                NavigationLink(value: AppRoute.myReplies) {
                    Label("我的回复", systemImage: "bubble.left.and.bubble.right")
                }
            }

            Section("发现") {
                NavigationLink(value: AppRoute.page(link: "/user/dyhSubscribe", title: "看看号订阅")) {
                    Label("看看号", systemImage: "newspaper")
                }
                NavigationLink(value: AppRoute.coolpic(tag: "全部")) {
                    Label("酷图", systemImage: "photo.on.rectangle.angled")
                }
                NavigationLink(value: AppRoute.page(link: "V9_HOME_TAB_RANKING", title: "热榜")) {
                    Label("酷安热榜", systemImage: "flame")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
    }
}
