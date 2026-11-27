import CoolapkKit
import SwiftUI
import UIKit

public struct HistoryListView: View {
    @Environment(AppState.self) private var appState
    @State private var cloudRows: [HomeFeedRow] = []
    @State private var isLoadingCloud = false
    @State private var cloudPage = 1
    @State private var hasMoreCloud = true
    @State private var isSelecting = false
    @State private var selectedLocalIDs: Set<String> = []

    public init() {}

    private var localIDs: Set<String> {
        Set(appState.historyAndFav.history.map(\.id))
    }

    private var mergedCloudRows: [HomeFeedRow] {
        guard appState.settings.enableCloudHistoryLoad && appState.accounts.isLoggedIn else { return [] }
        let existing = localIDs
        return cloudRows.filter { row in
            if case let .feed(feed) = row {
                return !existing.contains(feed.id)
            }
            return true
        }
    }

    public var body: some View {
        let showEmpty = appState.historyAndFav.history.isEmpty && mergedCloudRows.isEmpty && !isLoadingCloud
        Group {
            if showEmpty {
                ContentUnavailableView("暂无浏览历史", systemImage: "clock")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !appState.settings.enableCloudHistoryLoad && appState.accounts.isLoggedIn {
                            Text("已关闭云端浏览历史同步，仅显示本机记录（可在设置开启）。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        }

                        if !appState.historyAndFav.history.isEmpty {
                            Text("本机历史")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            ForEach(appState.historyAndFav.history) { entry in
                                SelectableCardWrapper(
                                    isSelecting: isSelecting,
                                    isSelected: selectedLocalIDs.contains(entry.id)
                                ) {
                                    if selectedLocalIDs.contains(entry.id) {
                                        selectedLocalIDs.remove(entry.id)
                                    } else {
                                        selectedLocalIDs.insert(entry.id)
                                    }
                                } content: {
                                    StoredFeedCardRow(
                                        feedID: entry.id,
                                        snapshot: entry.feed,
                                        fallbackTitle: entry.title,
                                        fallbackPreview: entry.preview,
                                        fallbackUsername: entry.username,
                                        fallbackAvatar: entry.avatar,
                                        fallbackDate: entry.visitedAt,
                                        badgeIsCloud: false,
                                        deleteTitle: "删除此条历史",
                                        onDelete: {
                                            appState.historyAndFav.removeHistory(id: entry.id)
                                        }
                                    )
                                }
                            }
                        }

                        if appState.settings.enableCloudHistoryLoad && appState.accounts.isLoggedIn {
                            Text("云端浏览历史")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)

                            if isLoadingCloud && cloudRows.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else if mergedCloudRows.isEmpty && cloudRows.isEmpty {
                                Text("暂无云端浏览历史")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ForEach(Array(mergedCloudRows.enumerated()), id: \.element.id) { idx, row in
                                    Group {
                                        if case let .feed(feed) = row {
                                            FeedRowView(feed: feed, originBadgeIsCloud: true)
                                        } else {
                                            HomeRowRenderer(row: row)
                                        }
                                    }
                                    .onAppear {
                                        if idx >= mergedCloudRows.count - 3 {
                                            Task { await loadMoreCloud() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, isSelecting ? 84 : 32)
                }
                .refreshable {
                    await syncCloudHistory(force: true)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .c001PageBackground()
        .navigationTitle("浏览历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !appState.historyAndFav.history.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(isSelecting ? "完成" : "多选") {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedLocalIDs.removeAll() }
                        }
                    }
                    if !isSelecting {
                        Button("清空本机", role: .destructive) {
                            appState.historyAndFav.clearHistory()
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                let allLocalIDs = Set(appState.historyAndFav.history.map(\.id))
                let allSelected = !allLocalIDs.isEmpty && selectedLocalIDs.isSuperset(of: allLocalIDs)
                BatchSelectionBottomBar(
                    selectedCount: selectedLocalIDs.count,
                    allSelected: allSelected,
                    deleteLabel: "删除历史",
                    isBusy: false,
                    onToggleSelectAll: {
                        if allSelected {
                            selectedLocalIDs.removeAll()
                        } else {
                            selectedLocalIDs = allLocalIDs
                        }
                    },
                    onDelete: {
                        let count = selectedLocalIDs.count
                        appState.historyAndFav.removeHistory(ids: selectedLocalIDs)
                        selectedLocalIDs.removeAll()
                        isSelecting = false
                        appState.showToast("已删除 \(count) 条本机历史")
                    }
                )
            }
        }
        .task(id: "\(appState.sessionVersion)|\(appState.settings.enableCloudHistoryLoad)") {
            await syncCloudHistory(force: false)
        }
    }

    private func syncCloudHistory(force: Bool) async {
        guard appState.settings.enableCloudHistoryLoad, appState.accounts.isLoggedIn else {
            cloudRows = []
            return
        }
        if !force && !cloudRows.isEmpty { return }
        isLoadingCloud = true
        defer { isLoadingCloud = false }
        cloudPage = 1
        do {
            let fetched = try await API.hitHistory(page: 1)
            cloudRows = fetched
            hasMoreCloud = !fetched.isEmpty
        } catch {
            if cloudRows.isEmpty {
                _ = await appState.handleAPIError(error)
            }
        }
    }

    private func loadMoreCloud() async {
        guard hasMoreCloud, !isLoadingCloud,
              appState.settings.enableCloudHistoryLoad,
              appState.accounts.isLoggedIn else { return }
        isLoadingCloud = true
        defer { isLoadingCloud = false }
        let next = cloudPage + 1
        if let fetched = try? await API.hitHistory(page: next) {
            var seen = Set(cloudRows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            cloudRows.append(contentsOf: unique)
            hasMoreCloud = !unique.isEmpty
            if hasMoreCloud { cloudPage = next }
        }
    }
}

private struct CloudFavoriteEntry: Identifiable, Hashable {
    let collectionID: String
    let collectionTitle: String
    let feed: FeedItem

    var id: String { "\(collectionID)-\(feed.id)" }
}

public struct FavoritesListView: View {
    @Environment(AppState.self) private var appState
    @State private var remoteCollections: [CollectionItem] = []
    @State private var cloudEntries: [CloudFavoriteEntry] = []
    @State private var selectedFolderID: String? = nil
    @State private var isSyncingCloud = false
    @State private var isSelecting = false
    @State private var selectedKeys: Set<String> = []
    @State private var isBatchDeleting = false

    public init() {}

    private var visibleLocalFavorites: [LocalFavoriteEntry] {
        guard let selectedFolderID else { return appState.historyAndFav.favorites }
        return appState.historyAndFav.favorites(inFolder: selectedFolderID)
    }

    private var visibleCloudFavorites: [CloudFavoriteEntry] {
        guard appState.settings.enableCloudFavoritesLoad else { return [] }
        let localIDSet = Set(visibleLocalFavorites.map(\.id))
        let scoped: [CloudFavoriteEntry]
        if let selectedFolderID {
            scoped = cloudEntries.filter { $0.collectionID == selectedFolderID }
        } else {
            var seenFeedIDs = Set<String>()
            scoped = cloudEntries.filter { seenFeedIDs.insert($0.feed.id).inserted }
        }
        return scoped.filter { !localIDSet.contains($0.feed.id) }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionHeader("收藏夹列表")
                    Spacer()
                    if isSyncingCloud {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 16)
                    }
                }

                if !appState.settings.enableCloudFavoritesLoad && appState.accounts.isLoggedIn {
                    Text("已关闭云端收藏夹加载，仅显示本机收藏数据（可在设置开启）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                // Local folders with "本地" corner badge
                ForEach(appState.historyAndFav.folders) { folder in
                    let isSelected = selectedFolderID == folder.id
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedFolderID = isSelected ? nil : folder.id
                        }
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill((folder.isCloudLinked ? Color.blue : Color.accentColor).opacity(0.14))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: folder.isCloudLinked ? "icloud" : "bookmark.fill")
                                        .foregroundStyle(folder.isCloudLinked ? Color.blue : Color.accentColor)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(folder.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    SourceOriginBadge(isCloud: false)
                                }
                                Text("\(appState.historyAndFav.count(inFolder: folder.id)) 条已缓存动态" + (isSelected ? " · 当前筛选中" : ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 20)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if folder.id != HistoryAndFavStore.defaultFolderID {
                            Button("删除收藏夹", role: .destructive) {
                                if selectedFolderID == folder.id { selectedFolderID = nil }
                                appState.historyAndFav.deleteFolder(id: folder.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Cloud collections with filter + open detail + "云端" corner badge
                if appState.settings.enableCloudFavoritesLoad && !remoteCollections.isEmpty {
                    ForEach(remoteCollections) { col in
                        let isSelected = selectedFolderID == col.id
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    selectedFolderID = isSelected ? nil : col.id
                                }
                                if !cloudEntries.contains(where: { $0.collectionID == col.id }) {
                                    Task { await loadCloudCollectionItems(col) }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    RemoteImageView(url: col.logo, maxPixelSize: 132)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(col.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            SourceOriginBadge(isCloud: true)
                                        }
                                        Text("\(col.itemNum) 项内容 · \(Formatting.count(col.followNum)) 关注" + (isSelected ? " · 当前筛选中" : ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                appState.push(.collection(id: col.id, initialTitle: col.title))
                            } label: {
                                Image(systemName: isSelected ? "line.3.horizontal.decrease.circle.fill" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .c001CardStyle(cornerRadius: 20)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 12)
                    }
                }

                HStack {
                    sectionHeader(selectedFolderID == nil ? "全部收藏内容" : "当前收藏夹内容")
                    Spacer()
                    if selectedFolderID != nil {
                        Button("查看全部") {
                            withAnimation(.snappy) { selectedFolderID = nil }
                        }
                        .font(.caption.weight(.medium))
                        .padding(.trailing, 16)
                    }
                }

                if visibleLocalFavorites.isEmpty && visibleCloudFavorites.isEmpty {
                    if isSyncingCloud {
                        ProgressView("正在同步云端收藏…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        Text("暂无收藏动态")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .c001CardStyle(cornerRadius: 20)
                            .padding(.horizontal, 12)
                    }
                } else {
                    ForEach(visibleLocalFavorites) { entry in
                        let key = "local:\(entry.id)"
                        SelectableCardWrapper(
                            isSelecting: isSelecting,
                            isSelected: selectedKeys.contains(key)
                        ) {
                            if selectedKeys.contains(key) {
                                selectedKeys.remove(key)
                            } else {
                                selectedKeys.insert(key)
                            }
                        } content: {
                            StoredFeedCardRow(
                                feedID: entry.id,
                                snapshot: entry.feed,
                                fallbackTitle: entry.title,
                                fallbackPreview: entry.preview,
                                fallbackUsername: entry.username,
                                fallbackAvatar: entry.avatar,
                                fallbackDate: entry.savedAt,
                                badgeIsCloud: entry.resolvedIsCloudSynced,
                                deleteTitle: "移除收藏",
                                onDelete: {
                                    appState.historyAndFav.removeFavorite(id: entry.id)
                                }
                            )
                        }
                    }

                    ForEach(visibleCloudFavorites) { entry in
                        let key = "cloud:\(entry.collectionID):\(entry.feed.id)"
                        SelectableCardWrapper(
                            isSelecting: isSelecting,
                            isSelected: selectedKeys.contains(key)
                        ) {
                            if selectedKeys.contains(key) {
                                selectedKeys.remove(key)
                            } else {
                                selectedKeys.insert(key)
                            }
                        } content: {
                            FeedRowView(
                                feed: entry.feed,
                                originBadgeIsCloud: true,
                                contextDeleteTitle: "移出云端收藏",
                                onContextDelete: {
                                    Task { await removeCloudFavorites([entry]) }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.bottom, isSelecting ? 84 : 32)
        }
        .refreshable {
            await syncCloudFavorites(force: true)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .c001PageBackground()
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !visibleLocalFavorites.isEmpty || !visibleCloudFavorites.isEmpty {
                    Button(isSelecting ? "完成" : "多选") {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedKeys.removeAll() }
                        }
                    }
                }

                Menu {
                    if appState.settings.enableCloudFavoritesLoad && appState.accounts.isLoggedIn {
                        Button {
                            Task { await syncCloudFavorites(force: true) }
                        } label: {
                            Label("立即同步云端收藏", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    Button {
                        if let data = appState.historyAndFav.exportBackupJSON(),
                           let str = String(data: data, encoding: .utf8) {
                            UIPasteboard.general.string = str
                            appState.showToast("已复制收藏夹备份 JSON")
                        }
                    } label: {
                        Label("导出备份 JSON", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        if let text = UIPasteboard.general.string,
                           let data = text.data(using: .utf8) {
                            let count = appState.historyAndFav.importBackupJSON(data)
                            appState.showToast(count > 0 ? "已导入 \(count) 条收藏" : "剪贴板中未检测到新的收藏数据")
                        } else {
                            appState.showToast("剪贴板为空")
                        }
                    } label: {
                        Label("从剪贴板导入 JSON", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                let allVisibleKeys = Set(visibleLocalFavorites.map { "local:\($0.id)" })
                    .union(visibleCloudFavorites.map { "cloud:\($0.collectionID):\($0.feed.id)" })
                let allSelected = !allVisibleKeys.isEmpty && selectedKeys.isSuperset(of: allVisibleKeys)
                BatchSelectionBottomBar(
                    selectedCount: selectedKeys.count,
                    allSelected: allSelected,
                    deleteLabel: "删除收藏",
                    isBusy: isBatchDeleting,
                    onToggleSelectAll: {
                        if allSelected {
                            selectedKeys.removeAll()
                        } else {
                            selectedKeys = allVisibleKeys
                        }
                    },
                    onDelete: {
                        Task { await deleteSelectedFavorites() }
                    }
                )
            }
        }
        .task(id: "\(appState.sessionVersion)|\(appState.settings.enableCloudFavoritesLoad)") {
            await syncCloudFavorites(force: false)
        }
    }

    private func deleteSelectedFavorites() async {
        guard !selectedKeys.isEmpty, !isBatchDeleting else { return }
        isBatchDeleting = true
        defer { isBatchDeleting = false }

        let localIDs = Set(selectedKeys.compactMap { key -> String? in
            key.hasPrefix("local:") ? String(key.dropFirst("local:".count)) : nil
        })
        let cloudToDelete = visibleCloudFavorites.filter { selectedKeys.contains("cloud:\($0.collectionID):\($0.feed.id)") }

        if !localIDs.isEmpty {
            appState.historyAndFav.removeFavorites(ids: localIDs)
        }
        if !cloudToDelete.isEmpty {
            await removeCloudFavorites(cloudToDelete)
        }

        let removedCount = localIDs.count + cloudToDelete.count
        selectedKeys.removeAll()
        isSelecting = false
        if removedCount > 0 {
            appState.showToast("已删除 \(removedCount) 条收藏")
        }
    }

    private func removeCloudFavorites(_ entries: [CloudFavoriteEntry]) async {
        var removedIDs = Set<String>()
        for entry in entries {
            do {
                try await API.collectFeedToCollection(
                    feedID: entry.feed.id,
                    addCollectionIDs: [],
                    cancelCollectionIDs: [entry.collectionID]
                )
                removedIDs.insert(entry.id)
            } catch {
                _ = await appState.handleAPIError(error)
            }
        }
        if !removedIDs.isEmpty {
            cloudEntries.removeAll { removedIDs.contains($0.id) }
        }
    }

    private func syncCloudFavorites(force: Bool) async {
        guard appState.settings.enableCloudFavoritesLoad,
              appState.accounts.isLoggedIn,
              let uid = appState.accounts.activeUID else {
            remoteCollections = []
            cloudEntries = []
            return
        }
        if !force && !remoteCollections.isEmpty { return }
        isSyncingCloud = true
        defer { isSyncingCloud = false }

        do {
            let cols = try await API.collectionList(uid: uid, page: 1)
            remoteCollections = cols
            let collected = await withTaskGroup(of: [CloudFavoriteEntry].self) { group in
                for col in cols.prefix(6) {
                    group.addTask {
                        let rows = (try? await API.collectionItems(id: col.id, page: 1)) ?? []
                        return rows.compactMap { row -> CloudFavoriteEntry? in
                            if case let .feed(feed) = row {
                                return CloudFavoriteEntry(collectionID: col.id, collectionTitle: col.title, feed: feed)
                            }
                            return nil
                        }
                    }
                }
                var merged: [CloudFavoriteEntry] = []
                for await batch in group {
                    merged.append(contentsOf: batch)
                }
                return merged
            }
            cloudEntries = collected
        } catch {
            if remoteCollections.isEmpty {
                _ = await appState.handleAPIError(error)
            }
        }
    }

    private func loadCloudCollectionItems(_ col: CollectionItem) async {
        guard let rows = try? await API.collectionItems(id: col.id, page: 1) else { return }
        let existingIDs = Set(cloudEntries.map(\.id))
        var appended: [CloudFavoriteEntry] = []
        for row in rows {
            if case let .feed(feed) = row {
                let entry = CloudFavoriteEntry(collectionID: col.id, collectionTitle: col.title, feed: feed)
                if !existingIDs.contains(entry.id) {
                    appended.append(entry)
                }
            }
        }
        if !appended.isEmpty {
            cloudEntries.append(contentsOf: appended)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}

public struct LocalFollowListView: View {
    @Environment(AppState.self) private var appState
    @State private var cloudUsers: [UserBrief] = []
    @State private var isLoadingCloud = false
    @State private var cloudPage = 1
    @State private var hasMoreCloud = true
    @State private var isSelecting = false
    @State private var selectedKeys: Set<String> = []
    @State private var isBatchDeleting = false

    public init() {}

    public var body: some View {
        let localEmpty = appState.localFollow.users.isEmpty
        let cloudEmpty = !appState.settings.enableCloudFollowLoad || cloudUsers.isEmpty
        let localUIDs = Set(appState.localFollow.users.map(\.uid))
        let uniqueCloudUsers = (appState.settings.enableCloudFollowLoad && appState.accounts.isLoggedIn)
            ? cloudUsers.filter { !localUIDs.contains($0.id) }
            : []

        Group {
            if localEmpty && cloudEmpty && !isLoadingCloud {
                ContentUnavailableView {
                    Label("暂无关注用户", systemImage: "person.badge.shield.checkmark")
                } description: {
                    Text(appState.accounts.isLoggedIn
                         ? "长按用户主页的关注按钮即可加入本机悄悄关注；也可在设置开启云端关注读取。"
                         : "游客模式下点击用户主页的本地关注按钮即可加入。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !appState.settings.enableCloudFollowLoad && appState.accounts.isLoggedIn {
                            Text("已关闭云端关注列表加载，仅显示本机关注（可在设置开启）。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                        }

                        if !appState.localFollow.users.isEmpty {
                            Text("本机关注（\(appState.localFollow.users.count)）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)

                            ForEach(appState.localFollow.users) { user in
                                let key = "local:\(user.uid)"
                                SelectableCardWrapper(
                                    isSelecting: isSelecting,
                                    isSelected: selectedKeys.contains(key)
                                ) {
                                    if selectedKeys.contains(key) {
                                        selectedKeys.remove(key)
                                    } else {
                                        selectedKeys.insert(key)
                                    }
                                } content: {
                                    UserRowView(
                                        user: UserBrief(
                                            id: user.uid,
                                            username: user.username,
                                            avatar: user.avatar,
                                            isFollowed: true,
                                            bio: "UID: \(user.uid)"
                                        ),
                                        originBadgeIsCloud: false,
                                        contextDeleteTitle: "取消本机关注",
                                        onContextDelete: {
                                            appState.localFollow.unfollow(uid: user.uid)
                                        }
                                    )
                                }
                            }
                        }

                        if appState.settings.enableCloudFollowLoad && appState.accounts.isLoggedIn {
                            Text("云端关注（\(uniqueCloudUsers.count)）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)

                            if isLoadingCloud && cloudUsers.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            } else if uniqueCloudUsers.isEmpty {
                                Text("暂无更多云端关注用户")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                            } else {
                                ForEach(Array(uniqueCloudUsers.enumerated()), id: \.element.id) { idx, user in
                                    let key = "cloud:\(user.id)"
                                    SelectableCardWrapper(
                                        isSelecting: isSelecting,
                                        isSelected: selectedKeys.contains(key)
                                    ) {
                                        if selectedKeys.contains(key) {
                                            selectedKeys.remove(key)
                                        } else {
                                            selectedKeys.insert(key)
                                        }
                                    } content: {
                                        UserRowView(
                                            user: user,
                                            originBadgeIsCloud: true,
                                            contextDeleteTitle: "取消云端关注",
                                            onContextDelete: {
                                                Task { await unfollowCloudUsers([user.id]) }
                                            }
                                        )
                                    }
                                    .onAppear {
                                        if idx >= uniqueCloudUsers.count - 4 {
                                            Task { await loadMoreCloud() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, isSelecting ? 84 : 32)
                }
                .refreshable {
                    await syncCloudFollows(force: true)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .c001PageBackground()
        .navigationTitle("关注列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !localEmpty || !uniqueCloudUsers.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "完成" : "多选") {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedKeys.removeAll() }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                let allKeys = Set(appState.localFollow.users.map { "local:\($0.uid)" })
                    .union(uniqueCloudUsers.map { "cloud:\($0.id)" })
                let allSelected = !allKeys.isEmpty && selectedKeys.isSuperset(of: allKeys)
                BatchSelectionBottomBar(
                    selectedCount: selectedKeys.count,
                    allSelected: allSelected,
                    deleteLabel: "取消关注",
                    isBusy: isBatchDeleting,
                    onToggleSelectAll: {
                        if allSelected {
                            selectedKeys.removeAll()
                        } else {
                            selectedKeys = allKeys
                        }
                    },
                    onDelete: {
                        Task { await deleteSelectedFollows() }
                    }
                )
            }
        }
        .task(id: "\(appState.sessionVersion)|\(appState.settings.enableCloudFollowLoad)") {
            await syncCloudFollows(force: false)
        }
    }

    private func deleteSelectedFollows() async {
        guard !selectedKeys.isEmpty, !isBatchDeleting else { return }
        isBatchDeleting = true
        defer { isBatchDeleting = false }

        let localToRemove = Set(selectedKeys.compactMap { key -> String? in
            key.hasPrefix("local:") ? String(key.dropFirst("local:".count)) : nil
        })
        let cloudToRemove = selectedKeys.compactMap { key -> String? in
            key.hasPrefix("cloud:") ? String(key.dropFirst("cloud:".count)) : nil
        }

        if !localToRemove.isEmpty {
            appState.localFollow.unfollow(uids: localToRemove)
        }
        if !cloudToRemove.isEmpty {
            await unfollowCloudUsers(cloudToRemove)
        }

        let removedCount = localToRemove.count + cloudToRemove.count
        selectedKeys.removeAll()
        isSelecting = false
        if removedCount > 0 {
            appState.showToast("已取消关注 \(removedCount) 位用户")
        }
    }

    private func unfollowCloudUsers(_ uids: [String]) async {
        var unfollowed = Set<String>()
        for targetUID in uids {
            do {
                try await API.followUser(uid: targetUID, follow: false)
                unfollowed.insert(targetUID)
            } catch {
                _ = await appState.handleAPIError(error)
            }
        }
        if !unfollowed.isEmpty {
            cloudUsers.removeAll { unfollowed.contains($0.id) }
        }
    }

    private func syncCloudFollows(force: Bool) async {
        guard appState.settings.enableCloudFollowLoad,
              appState.accounts.isLoggedIn,
              let uid = appState.accounts.activeUID else {
            cloudUsers = []
            return
        }
        if !force && !cloudUsers.isEmpty { return }
        isLoadingCloud = true
        defer { isLoadingCloud = false }
        cloudPage = 1
        let fetched = (try? await API.userList(uid: uid, followers: false, page: 1)) ?? []
        cloudUsers = fetched
        hasMoreCloud = !fetched.isEmpty
    }

    private func loadMoreCloud() async {
        guard hasMoreCloud, !isLoadingCloud,
              appState.settings.enableCloudFollowLoad,
              appState.accounts.isLoggedIn,
              let uid = appState.accounts.activeUID else { return }
        isLoadingCloud = true
        defer { isLoadingCloud = false }
        let next = cloudPage + 1
        if let fetched = try? await API.userList(uid: uid, followers: false, page: next) {
            var seen = Set(cloudUsers.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            cloudUsers.append(contentsOf: unique)
            hasMoreCloud = !unique.isEmpty
            if hasMoreCloud { cloudPage = next }
        }
    }
}

public struct UserRecentVisitsView: View {
    public init() {}

    public var body: some View {
        LoggedInPagedActivityView(
            title: "我的常去",
            emptyTitle: "暂无常去记录",
            emptyIcon: "location"
        ) { uid, page in
            try await API.userRecentVisits(uid: uid, page: page)
        }
    }
}

public struct UserLikesListView: View {
    public init() {}

    public var body: some View {
        LoggedInPagedActivityView(
            title: "我的赞",
            emptyTitle: "暂无点赞动态",
            emptyIcon: "hand.thumbsup"
        ) { uid, page in
            try await API.userLikeFeeds(uid: uid, page: page)
        }
    }
}

public struct UserRepliesListView: View {
    private enum ReplyBoxTab: String, CaseIterable, Identifiable {
        case sent = "我的回复"
        case received = "收到的回复"
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var appState
    @State private var activeTab: ReplyBoxTab = .sent
    @State private var scrolledTab: ReplyBoxTab? = .sent

    public init() {}

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(ReplyBoxTab.allCases) { tab in
                    LoggedInPagedActivityPage(
                        emptyTitle: "暂无\(tab.rawValue)",
                        emptyIcon: "bubble.left.and.bubble.right"
                    ) { uid, page in
                        try await API.userReplies(uid: uid, received: tab == .received, page: page)
                    }
                    .containerRelativeFrame(.horizontal)
                    .frame(maxHeight: .infinity)
                    .id(tab)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledTab)
        .scrollClipDisabled()
        .ignoresSafeArea(.container, edges: .bottom)
        .c001PageBackground()
        .safeAreaBar(edge: .top, spacing: 0) {
            FloatingTabStrip(
                items: ReplyBoxTab.allCases,
                selection: activeTab,
                titleProvider: \.rawValue,
                onSelect: { activeTab = $0 }
            )
        }
        .navigationTitle("我的回复")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scrolledTab) { _, next in
            if let next, next != activeTab { activeTab = next }
        }
        .onChange(of: activeTab) { _, next in
            if scrolledTab != next {
                withAnimation(.snappy(duration: 0.22)) { scrolledTab = next }
            }
        }
    }
}

private struct LoggedInPagedActivityView: View {
    let title: String
    let emptyTitle: String
    let emptyIcon: String
    let loader: @Sendable (String, Int) async throws -> [HomeFeedRow]

    var body: some View {
        LoggedInPagedActivityPage(emptyTitle: emptyTitle, emptyIcon: emptyIcon, loader: loader)
            .c001PageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LoggedInPagedActivityPage: View {
    let emptyTitle: String
    let emptyIcon: String
    let loader: @Sendable (String, Int) async throws -> [HomeFeedRow]

    @Environment(AppState.self) private var appState
    @State private var rows: [HomeFeedRow] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasLoaded = false
    @State private var hasMore = true
    @State private var page = 1
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !appState.accounts.isLoggedIn {
                ContentUnavailableView {
                    Label("登录后查看", systemImage: emptyIcon)
                } description: {
                    Text("需要登录酷安账号后读取云端记录。")
                } actions: {
                    Button("去登录") {
                        appState.showLoginSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if (!hasLoaded || isLoading) && rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, rows.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await reload(force: true) } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptyIcon)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            HomeRowRenderer(row: row)
                                .onAppear {
                                    if idx >= rows.count - 4 {
                                        Task { await loadMore() }
                                    }
                                }
                        }
                        if isLoadingMore {
                            ProgressView().padding(.vertical, 16)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await reload(force: true)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
        }
        .task(id: appState.sessionVersion) {
            await reload(force: false)
        }
    }

    private func reload(force: Bool) async {
        guard appState.accounts.isLoggedIn, let uid = appState.accounts.activeUID else {
            rows = []
            return
        }
        if !force && hasLoaded && !rows.isEmpty { return }
        isLoading = true
        errorMessage = nil
        page = 1
        hasMore = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let fetched = try await loader(uid, 1)
            rows = fetched
            hasMore = !fetched.isEmpty
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
                _ = await appState.handleAPIError(error)
            }
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore,
              appState.accounts.isLoggedIn, let uid = appState.accounts.activeUID else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = page + 1
        do {
            let fetched = try await loader(uid, next)
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        } catch {
            // Keep existing list on pagination failure.
        }
    }
}

private struct StoredFeedCardRow: View {
    let feedID: String
    let snapshot: FeedItem?
    let fallbackTitle: String
    let fallbackPreview: String
    let fallbackUsername: String
    let fallbackAvatar: String
    let fallbackDate: Date
    let badgeIsCloud: Bool?
    let deleteTitle: String
    let onDelete: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var hydrated: FeedItem?
    @State private var didAttemptHydration = false
    @State private var transitionSeed = UUID().uuidString

    var body: some View {
        Group {
            if let feed = snapshot ?? hydrated {
                FeedRowView(
                    feed: feed,
                    originBadgeIsCloud: badgeIsCloud,
                    contextDeleteTitle: deleteTitle,
                    onContextDelete: onDelete
                )
            } else {
                legacyFallbackCard
            }
        }
        .task(id: feedID) {
            guard snapshot == nil, hydrated == nil, !didAttemptHydration, !feedID.isEmpty else { return }
            didAttemptHydration = true
            if let fetched = try? await API.feedDetail(id: feedID) {
                hydrated = fetched
                appState.historyAndFav.backfillSnapshot(fetched)
            }
        }
    }

    private var legacyFallbackCard: some View {
        let tid = "stored-\(feedID)-\(transitionSeed)"
        return Button {
            appState.push(.feed(id: feedID, transitionID: tid))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AvatarView(url: fallbackAvatar, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fallbackUsername.isEmpty ? "酷友" : fallbackUsername)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(Formatting.relativeTime(fallbackDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let badgeIsCloud {
                        SourceOriginBadge(isCloud: badgeIsCloud)
                    }
                }

                if !fallbackTitle.isEmpty {
                    Text(fallbackTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if !fallbackPreview.isEmpty {
                    Text(fallbackPreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contextMenu {
                Button(deleteTitle, role: .destructive) {
                    onDelete()
                }
            }
            .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct SelectableCardWrapper<Content: View>: View {
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.leading, 14)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            content()
                .allowsHitTesting(!isSelecting)
        }
        .overlay {
            if isSelecting {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggle)
            }
        }
        .animation(.snappy(duration: 0.2), value: isSelecting)
    }
}

private struct BatchSelectionBottomBar: View {
    let selectedCount: Int
    let allSelected: Bool
    let deleteLabel: String
    let isBusy: Bool
    let onToggleSelectAll: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(allSelected ? "取消全选" : "全选", action: onToggleSelectAll)
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)

                Spacer()

                Text("已选 \(selectedCount) 项")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 5) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text("\(deleteLabel)\(selectedCount > 0 ? " (\(selectedCount))" : "")")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        selectedCount > 0 ? Color.red.opacity(0.16) : Color.secondary.opacity(0.1),
                        in: Capsule()
                    )
                    .foregroundStyle(selectedCount > 0 ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || isBusy)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}
