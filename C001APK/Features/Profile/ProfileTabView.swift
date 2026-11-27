import CoolapkKit
import SwiftUI

public struct ProfileTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if appState.accounts.isLoggedIn {
                    let profile = appState.currentUserProfile
                    let tid = "my-profile-\(transitionSeed)"
                    Button {
                        if let uid = appState.accounts.activeUID {
                            appState.push(.user(
                                uid: uid,
                                initialUsername: profile?.username ?? appState.accounts.activeAccount?.username,
                                initialAvatar: profile?.avatar ?? appState.accounts.activeAccount?.userAvatar,
                                transitionID: tid,
                                initialTab: "动态"
                            ))
                        }
                    } label: {
                        loggedInCard
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 20)
                    .padding(.horizontal, 12)

                    profileStatsRow(
                        feedsCount: Formatting.count(profile?.feedNum ?? 0),
                        followCount: Formatting.count(profile?.followNum ?? appState.localFollow.users.count),
                        fansCount: Formatting.count(profile?.fansNum ?? 0)
                    )
                    .padding(.horizontal, 12)
                } else {
                    guestCard
                        .padding(.horizontal, 12)

                    profileStatsRow(
                        feedsCount: "0",
                        followCount: "\(appState.localFollow.users.count)",
                        fansCount: "0"
                    )
                    .padding(.horizontal, 12)
                }

                VStack(spacing: 0) {
                    menuRow(title: "消息中心", icon: "bell.fill", tint: .orange, badge: appState.unreadSummary.total) {
                        appState.push(.messages)
                    }
                    Divider().padding(.leading, 52)
                    menuRow(title: "收藏", icon: "star.fill", tint: .yellow, subtitle: "\(appState.historyAndFav.favorites.count + appState.historyAndFav.cachedCloudEntries.count)") {
                        appState.push(.favorites)
                    }
                    Divider().padding(.leading, 52)
                    menuRow(title: "浏览历史", icon: "clock.fill", tint: .blue, subtitle: "\(appState.historyAndFav.history.count)") {
                        appState.push(.history)
                    }
                    Divider().padding(.leading, 52)
                    menuRow(title: "关注列表", icon: "person.2.fill", tint: .green, subtitle: "\(appState.localFollow.users.count)") {
                        appState.push(.localFollowList)
                    }

                    if appState.accounts.isLoggedIn {
                        Divider().padding(.leading, 52)
                        menuRow(title: "我的常去", icon: "location.fill", tint: .teal) {
                            appState.push(.myRecentVisits)
                        }
                        Divider().padding(.leading, 52)
                        menuRow(title: "我的赞", icon: "hand.thumbsup.fill", tint: .pink) {
                            appState.push(.myLikes)
                        }
                        Divider().padding(.leading, 52)
                        menuRow(title: "我的回复", icon: "bubble.left.and.bubble.right.fill", tint: .indigo) {
                            appState.push(.myReplies)
                        }
                    }
                }
                .c001CardStyle(cornerRadius: 20)
                .padding(.horizontal, 12)

                VStack(spacing: 0) {
                    menuRow(title: "多账号管理", icon: "person.crop.circle.badge.plus", tint: .purple, subtitle: "\(appState.accounts.accounts.count)") {
                        appState.push(.accounts)
                    }
                    Divider().padding(.leading, 52)
                    menuRow(title: "黑名单与屏蔽", icon: "hand.raised.fill", tint: .red) {
                        appState.push(.blacklist(isTopic: false))
                    }
                    Divider().padding(.leading, 52)
                    menuRow(title: "设置", icon: "gearshape.fill", tint: .gray) {
                        appState.push(.settings)
                    }
                    Divider().padding(.leading, 52)
                    menuRow(title: "关于 C001APK", icon: "info.circle.fill", tint: .cyan) {
                        appState.push(.about)
                    }
                }
                .c001CardStyle(cornerRadius: 20)
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
            .padding(.bottom, 88)
        }
        .refreshable {
            await appState.refreshCurrentUserProfile()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .c001PageBackground()
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    appState.push(.messages)
                } label: {
                    Image(systemName: appState.unreadSummary.total > 0 ? "bell.badge.fill" : "bell")
                }

                Button {
                    appState.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            if appState.accounts.isLoggedIn && appState.currentUserProfile == nil {
                await appState.refreshCurrentUserProfile()
            }
        }
    }

    private var loggedInCard: some View {
        let profile = appState.currentUserProfile
        let account = appState.accounts.activeAccount
        return HStack(spacing: 14) {
            AvatarView(url: profile?.avatar ?? account?.userAvatar ?? "", size: 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile?.username ?? account?.username ?? "已登录用户")
                        .font(.title3.weight(.bold))
                    if let lv = profile?.level, lv > 0 {
                        Text("Lv.\(lv)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let bio = profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("UID: \(account?.uid ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .c001CardStyle(cornerRadius: 20)
    }

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 46))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("游客模式")
                        .font(.title3.weight(.bold))
                    Text("无需登录即可浏览动态、使用本地收藏与本地关注。登录后可发表评论与同步通知。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    appState.showLoginSheet = true
                } label: {
                    Label("账号 / Cookie 登录", systemImage: "key.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appState.showWebLoginSheet = true
                } label: {
                    Label("网页登录", systemImage: "safari.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .c001CardStyle(cornerRadius: 20)
    }

    private func profileStatsRow(feedsCount: String, followCount: String, fansCount: String) -> some View {
        let profile = appState.currentUserProfile
        let account = appState.accounts.activeAccount
        return HStack(spacing: 10) {
            statActionCard(title: "动态", count: feedsCount, icon: "doc.richtext") {
                if let uid = appState.accounts.activeUID, appState.accounts.isLoggedIn {
                    appState.push(.user(
                        uid: uid,
                        initialUsername: profile?.username ?? account?.username,
                        initialAvatar: profile?.avatar ?? account?.userAvatar,
                        initialTab: "动态"
                    ))
                } else {
                    appState.showLoginSheet = true
                }
            }

            statActionCard(title: "关注", count: followCount, icon: "person.2") {
                if let uid = appState.accounts.activeUID, appState.accounts.isLoggedIn {
                    if appState.settings.enableCloudFollowLoad {
                        appState.push(.user(
                            uid: uid,
                            initialUsername: profile?.username ?? account?.username,
                            initialAvatar: profile?.avatar ?? account?.userAvatar,
                            initialTab: "关注"
                        ))
                    } else {
                        appState.push(.localFollowList)
                    }
                } else {
                    appState.push(.localFollowList)
                }
            }

            statActionCard(title: "粉丝", count: fansCount, icon: "heart.circle") {
                if let uid = appState.accounts.activeUID, appState.accounts.isLoggedIn {
                    appState.push(.user(
                        uid: uid,
                        initialUsername: profile?.username ?? account?.username,
                        initialAvatar: profile?.avatar ?? account?.userAvatar,
                        initialTab: "粉丝"
                    ))
                } else {
                    appState.showLoginSheet = true
                }
            }
        }
    }

    private func statActionCard(title: String, count: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(count)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .c001CardStyle(cornerRadius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func menuRow(
        title: String,
        icon: String,
        tint: Color,
        subtitle: String? = nil,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                } else if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
