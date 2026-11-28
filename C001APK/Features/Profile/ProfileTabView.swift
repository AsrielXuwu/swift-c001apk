import CoolapkKit
import SwiftUI

public struct ProfileTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init() {}

    public var body: some View {
        List {
            Section {
                if let active = appState.accounts.activeAccount {
                    let profile = appState.currentUserProfile
                    let displayName = profile?.username.isEmpty == false ? profile!.username : active.displayName
                    let avatarURL = profile?.avatar.isEmpty == false ? profile!.avatar : active.avatar
                    let level = profile?.level ?? active.level
                    let headerSourceID = "prof-header-\(transitionSeed)-\(active.uid)"

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
                            AvatarView(url: avatarURL, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(displayName.isEmpty ? "UID: \(active.uid)" : displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Lv.\(level)")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
                                }
                                if let bio = profile?.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("UID: \(active.uid)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .applyZoomSource(id: headerSourceID, in: zoomNamespace)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("游客模式")
                                .font(.headline)
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
                let profile = appState.currentUserProfile
                let active = appState.accounts.activeAccount
                let feedsCount = Formatting.count(profile?.feedNum ?? 0)
                let followCount = Formatting.count(profile?.followNum ?? appState.localFollow.users.count)
                let fansCount = Formatting.count(profile?.fansNum ?? 0)

                HStack(spacing: 0) {
                    statCell(title: "动态", count: feedsCount, sourceKey: "feeds") { sourceID in
                        if let active {
                            appState.push(.user(
                                uid: active.uid,
                                initialUsername: profile?.username ?? active.displayName,
                                initialAvatar: profile?.avatar ?? active.avatar,
                                transitionID: sourceID,
                                initialTab: "动态"
                            ))
                        } else {
                            appState.showLoginSheet = true
                        }
                    }

                    Divider().frame(height: 28)

                    statCell(title: "关注", count: followCount, sourceKey: "follow") { sourceID in
                        if let active, appState.settings.enableCloudFollowLoad {
                            appState.push(.user(
                                uid: active.uid,
                                initialUsername: profile?.username ?? active.displayName,
                                initialAvatar: profile?.avatar ?? active.avatar,
                                transitionID: sourceID,
                                initialTab: "关注"
                            ))
                        } else {
                            appState.push(.localFollowList(transitionID: sourceID))
                        }
                    }

                    Divider().frame(height: 28)

                    statCell(title: "粉丝", count: fansCount, sourceKey: "fans") { sourceID in
                        if let active {
                            appState.push(.user(
                                uid: active.uid,
                                initialUsername: profile?.username ?? active.displayName,
                                initialAvatar: profile?.avatar ?? active.avatar,
                                transitionID: sourceID,
                                initialTab: "粉丝"
                            ))
                        } else {
                            appState.showLoginSheet = true
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("我的内容") {
                zoomRouteRow(title: "我的关注（动态与板块）", systemImage: "person.2", key: "followFeed") { id in
                    .followFeed(transitionID: id)
                }
                zoomRouteRow(title: "我的收藏", systemImage: "star", key: "favorites") { id in
                    .favorites(transitionID: id)
                }
                zoomRouteRow(title: "浏览历史", systemImage: "clock", key: "history") { id in
                    .history(transitionID: id)
                }
                zoomRouteRow(
                    title: appState.accounts.isLoggedIn ? "悄悄关注" : "本机关注",
                    systemImage: "person.badge.shield.checkmark",
                    badge: "\(appState.localFollow.users.count)",
                    key: "localFollow"
                ) { id in
                    .localFollowList(transitionID: id)
                }
                zoomRouteRow(title: "我的常去", systemImage: "location", key: "recentVisits") { id in
                    .myRecentVisits(transitionID: id)
                }
                zoomRouteRow(title: "我的赞", systemImage: "hand.thumbsup", key: "myLikes") { id in
                    .myLikes(transitionID: id)
                }
                zoomRouteRow(title: "我的回复", systemImage: "bubble.left.and.bubble.right", key: "myReplies") { id in
                    .myReplies(transitionID: id)
                }
            }

            Section("发现") {
                zoomRouteRow(title: "分区与发现广场", systemImage: "square.grid.2x2", key: "partitionHub") { id in
                    .partitionHub(transitionID: id)
                }
                zoomRouteRow(title: "数码品牌分类库", systemImage: "cpu", key: "productCat") { id in
                    .productCategoryBrowser(transitionID: id)
                }
                zoomRouteRow(title: "看看号", systemImage: "newspaper", key: "dyhSub") { id in
                    .page(link: "/user/dyhSubscribe", title: "看看号订阅", transitionID: id)
                }
                zoomRouteRow(title: "酷图", systemImage: "photo.on.rectangle.angled", key: "coolpic") { id in
                    .coolpic(tag: "全部", transitionID: id)
                }
                zoomRouteRow(title: "酷安热榜", systemImage: "flame", key: "hotRank") { id in
                    .page(link: "V9_HOME_TAB_RANKING", title: "热榜", transitionID: id)
                }
            }

            Section("账号与设置") {
                zoomRouteRow(
                    title: "账号管理",
                    systemImage: "person.2.badge.key",
                    badge: "已保存 \(appState.accounts.accounts.count) 个",
                    key: "accounts"
                ) { id in
                    .accounts(transitionID: id)
                }
                zoomRouteRow(title: "内容屏蔽与过滤", systemImage: "line.3.horizontal.decrease.circle", key: "filter") { id in
                    .contentFilterSettings(transitionID: id)
                }
                zoomRouteRow(title: "关于 Swift C001APK", systemImage: "info.circle", key: "about") { id in
                    .about(transitionID: id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
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
                    appState.push(.settings())
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

    private func statCell(
        title: String,
        count: String,
        sourceKey: String,
        action: @escaping (String) -> Void
    ) -> some View {
        let sourceID = "prof-stat-\(transitionSeed)-\(sourceKey)"
        return Button {
            action(sourceID)
        } label: {
            VStack(spacing: 3) {
                Text(count)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .applyZoomSource(id: sourceID, in: zoomNamespace)
        }
        .buttonStyle(.plain)
    }

    private func zoomRouteRow(
        title: String,
        systemImage: String,
        badge: String = "",
        key: String,
        routeBuilder: @escaping (String) -> AppRoute
    ) -> some View {
        let sourceID = "prof-row-\(transitionSeed)-\(key)"
        return Button {
            appState.push(routeBuilder(sourceID))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 24, alignment: .center)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if !badge.isEmpty {
                    Text(badge)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .applyZoomSource(id: sourceID, in: zoomNamespace)
        }
        .buttonStyle(.plain)
    }
}
