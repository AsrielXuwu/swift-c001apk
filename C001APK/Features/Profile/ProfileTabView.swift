import CoolapkKit
import SwiftUI

public struct ProfileTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init() {}

    private struct QuickCardItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let requiresLogin: Bool
        let route: AppRoute
    }

    private var myContentCards: [QuickCardItem] {
        [
            QuickCardItem(id: "qc-history", title: "浏览历史", subtitle: "足迹与记录", icon: "clock.arrow.circlepath", tint: .blue, requiresLogin: false, route: .history),
            QuickCardItem(id: "qc-fav", title: "我的收藏", subtitle: "本地与云端", icon: "star.fill", tint: .orange, requiresLogin: false, route: .favorites),
            QuickCardItem(id: "qc-localfollow", title: appState.accounts.isLoggedIn ? "悄悄关注" : "本机关注", subtitle: "\(appState.localFollow.users.count) 人", icon: "person.badge.shield.checkmark", tint: .purple, requiresLogin: false, route: .localFollowList),
            QuickCardItem(id: "qc-recent", title: "最近常去", subtitle: "常逛话题数码", icon: "safari.fill", tint: .cyan, requiresLogin: false, route: .myRecentVisits),
            QuickCardItem(id: "qc-likes", title: "我赞过的", subtitle: "点赞动态归档", icon: "hand.thumbsup.fill", tint: .pink, requiresLogin: false, route: .myLikes),
            QuickCardItem(id: "qc-replies", title: "我的回复", subtitle: "发出与收到的评论", icon: "text.bubble.fill", tint: .green, requiresLogin: false, route: .myReplies)
        ]
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                profileHeaderSection

                myContentGridSection

                partitionDiscoveryCardSection

                settingsCardSection
            }
            .padding(.vertical, 10)
            .padding(.bottom, 76)
        }
        .c001PageBackground()
        .c001NativeTopBar()
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    let sourceID = "prof-part-btn-\(transitionSeed)"
                    appState.push(.partitionHub(transitionID: sourceID))
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityLabel("分区与发现")

                Button {
                    appState.push(.messages)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                        if appState.hasUnreadMessages {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -2)
                        }
                    }
                }
                .accessibilityLabel("消息")

                Button {
                    appState.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
        .refreshable {
            await appState.refreshLoginAndBadge()
        }
        .task(id: appState.accounts.activeUID) {
            if appState.accounts.isLoggedIn && appState.currentUserProfile == nil {
                await appState.refreshLoginAndBadge()
            }
        }
    }

    @ViewBuilder
    private var profileHeaderSection: some View {
        if let active = appState.accounts.activeAccount {
            let profile = appState.currentUserProfile
            let displayName = profile?.username.isEmpty == false ? profile!.username : active.displayName
            let avatarURL = profile?.avatar.isEmpty == false ? profile!.avatar : active.avatar
            let level = profile?.level ?? active.level
            let headerSourceID = "my-profile-header-\(transitionSeed)-\(active.uid)"

            VStack(spacing: 12) {
                Button {
                    appState.push(.user(
                        uid: active.uid,
                        initialUsername: displayName,
                        initialAvatar: avatarURL,
                        transitionID: headerSourceID,
                        initialTab: "动态"
                    ))
                } label: {
                    HStack(spacing: 14) {
                        AvatarView(url: avatarURL, size: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(displayName.isEmpty ? "UID: \(active.uid)" : displayName)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Lv.\(level)")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                                    .foregroundStyle(Color.accentColor)
                            }
                            if let bio = profile?.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            } else {
                                Text("UID: \(active.uid)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().opacity(0.4)
                HStack(spacing: 0) {
                    statButton(title: "动态", count: profile?.feedNum ?? 0, tab: "动态", uid: active.uid, name: displayName, avatar: avatarURL)
                    statButton(title: "关注", count: profile?.followNum ?? appState.localFollow.users.count, tab: "关注", uid: active.uid, name: displayName, avatar: avatarURL)
                    statButton(title: "粉丝", count: profile?.fansNum ?? 0, tab: "粉丝", uid: active.uid, name: displayName, avatar: avatarURL)
                    statButton(title: "获赞", count: profile?.likeNum ?? 0, tab: "赞过", uid: active.uid, name: displayName, avatar: avatarURL)
                }
            }
            .padding(16)
            .c001CardStyle(cornerRadius: 22)
            .applyZoomSource(id: headerSourceID, in: zoomNamespace, cornerRadius: 22)
            .padding(.horizontal, 12)
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("游客模式")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
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
            }
            .padding(16)
            .c001CardStyle(cornerRadius: 22)
            .padding(.horizontal, 12)
        }
    }

    private func statButton(title: String, count: Int, tab: String, uid: String, name: String, avatar: String) -> some View {
        let sourceID = "my-stat-\(transitionSeed)-\(tab)"
        return Button {
            if tab == "关注" && !appState.settings.enableCloudFollowLoad {
                appState.push(.localFollowList)
            } else {
                appState.push(.user(uid: uid, initialUsername: name, initialAvatar: avatar, transitionID: sourceID, initialTab: tab))
            }
        } label: {
            VStack(spacing: 2) {
                Text(Formatting.count(count))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }

    private var myContentGridSection: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return VStack(alignment: .leading, spacing: 10) {
            Text("我的内容")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(myContentCards) { card in
                    let sourceID = "prof-qc-\(transitionSeed)-\(card.id)"
                    Button {
                        appState.push(card.route)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(card.tint.opacity(0.15))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Image(systemName: card.icon)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(card.tint)
                                    }
                                Spacer()
                            }
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(card.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .c001CardStyle(cornerRadius: 18)
                        .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var partitionDiscoveryCardSection: some View {
        let allSourceID = "prof-part-all-\(transitionSeed)"
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("分区与发现")
                        .font(.headline)
                }
                Spacer()
                Button {
                    appState.push(.partitionHub(transitionID: allSourceID))
                } label: {
                    HStack(spacing: 4) {
                        Text("全部分区")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .applyZoomSource(id: allSourceID, in: zoomNamespace, cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(PartitionHubView.featuredShortcuts) { item in
                    let sourceID = "prof-part-item-\(transitionSeed)-\(item.id)"
                    Button {
                        switch item.action {
                        case let .route(route):
                            switch route {
                            case .productCategoryBrowser:
                                appState.push(.productCategoryBrowser(transitionID: sourceID))
                            case .partitionHub:
                                appState.push(.partitionHub(transitionID: sourceID))
                            default:
                                appState.push(route)
                            }
                        case let .rawLink(link, title):
                            appState.openRawLink(link, title: title, transitionID: sourceID)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(item.tint.opacity(0.15))
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Image(systemName: item.systemImage)
                                        .font(.headline)
                                        .foregroundStyle(item.tint)
                                }
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .c001CardStyle(cornerRadius: 22)
        .padding(.horizontal, 12)
    }

    private var settingsCardSection: some View {
        VStack(spacing: 0) {
            settingRow(title: "账号管理", trailingText: "已保存 \(appState.accounts.accounts.count) 个", icon: "person.2.badge.key.fill", tint: .blue) {
                appState.push(.accounts)
            }
            Divider().padding(.leading, 48)
            settingRow(title: "内容过滤与屏蔽", icon: "line.3.horizontal.decrease.circle.fill", tint: .teal) {
                appState.push(.contentFilterSettings)
            }
            Divider().padding(.leading, 48)
            settingRow(title: "应用设置", icon: "gearshape.fill", tint: .gray) {
                appState.push(.settings)
            }
            Divider().padding(.leading, 48)
            settingRow(title: "关于 c001apk", icon: "info.circle.fill", tint: .indigo) {
                appState.push(.about)
            }
        }
        .padding(.vertical, 4)
        .c001CardStyle(cornerRadius: 22)
        .padding(.horizontal, 12)
    }

    private func settingRow(title: String, trailingText: String = "", icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if !trailingText.isEmpty {
                    Text(trailingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
