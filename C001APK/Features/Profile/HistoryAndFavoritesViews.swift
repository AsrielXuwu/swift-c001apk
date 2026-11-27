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

private enum NewFolderLocationMode: String, CaseIterable, Identifiable {
    case local = "本机收藏夹"
    case cloud = "云端收藏夹"
    case both = "本机 + 云端同名"

    var id: String { rawValue }
}

private struct MergedFavoriteFolderItem: Identifiable, Hashable {
    let key: String
    let title: String
    let localFolder: LocalCollectionFolder?
    let cloudCollection: CollectionItem?
    let localItemCount: Int
    let cloudItemCount: Int

    var id: String { key }
    var hasLocal: Bool { localFolder != nil }
    var hasCloud: Bool { cloudCollection != nil }
    var logoURL: String { cloudCollection?.logo ?? "" }

    var isDeletable: Bool {
        let localCanDelete = (localFolder != nil && localFolder?.id != HistoryAndFavStore.defaultFolderID)
        let cloudCanDelete = (cloudCollection != nil)
        return localCanDelete || cloudCanDelete
    }

    var subtitleText: String {
        if hasLocal && hasCloud {
            let followText = cloudCollection.map { " · \(Formatting.count($0.followNum)) 关注" } ?? ""
            return "本机 \(localItemCount) 条 · 云端 \(cloudItemCount) 条\(followText)"
        } else if let col = cloudCollection {
            return "\(max(col.itemNum, cloudItemCount)) 项云端内容 · \(Formatting.count(col.followNum)) 关注"
        } else {
            return "\(localItemCount) 条本机收藏"
        }
    }
}

private struct UnifiedFavoriteFeedItem: Identifiable {
    let feedID: String
    let localEntry: LocalFavoriteEntry?
    let cloudEntry: CachedCloudFavoriteEntry?
    let allCloudEntriesForFeed: [CachedCloudFavoriteEntry]

    var id: String {
        if let localEntry, !localEntry.resolvedIsCloudSynced {
            return "local:\(feedID)"
        }
        if let cloudEntry {
            return "cloud:\(cloudEntry.collectionID):\(feedID)"
        }
        return "fav:\(feedID)"
    }

    var isCloud: Bool {
        if cloudEntry != nil { return true }
        return localEntry?.resolvedIsCloudSynced ?? false
    }

    var isLocal: Bool {
        if let localEntry, !localEntry.resolvedIsCloudSynced {
            return true
        }
        return false
    }
}

public struct FavoritesListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFolderKey: String? = nil
    @State private var isSyncingCloud = false
    @State private var isSelectingItems = false
    @State private var selectedItemIDs: Set<String> = []
    @State private var isManagingFolders = false
    @State private var selectedFolderKeys: Set<String> = []
    @State private var isBatchDeleting = false
    @State private var showCreateFolderSheet = false
    @State private var newFolderTitle = ""
    @State private var newFolderDescription = ""
    @State private var newFolderLocation: NewFolderLocationMode = .local
    @State private var newFolderIsOpen = false
    @State private var isCreatingFolder = false

    public init() {}

    private var activeCloudCollections: [CollectionItem] {
        guard appState.settings.enableCloudFavoritesLoad && appState.accounts.isLoggedIn else { return [] }
        return appState.historyAndFav.cachedCloudCollections
    }

    private var activeCloudEntries: [CachedCloudFavoriteEntry] {
        guard appState.settings.enableCloudFavoritesLoad && appState.accounts.isLoggedIn else { return [] }
        return appState.historyAndFav.cachedCloudEntries
    }

    private var mergedFolders: [MergedFavoriteFolderItem] {
        let pureLocalFolders = appState.historyAndFav.folders.filter { folder in
            if !folder.isCloudLinked { return true }
            return appState.historyAndFav.favorites.contains { $0.resolvedCollectionID == folder.id && !$0.resolvedIsCloudSynced }
        }
        let cloudCols = activeCloudCollections

        var orderedTitles: [String] = []
        var localByTitle: [String: LocalCollectionFolder] = [:]
        var cloudByTitle: [String: CollectionItem] = [:]

        for folder in pureLocalFolders {
            let norm = HistoryAndFavStore.normalizedFolderTitle(folder.title)
            guard !norm.isEmpty else { continue }
            if localByTitle[norm] == nil {
                localByTitle[norm] = folder
                if !orderedTitles.contains(norm) {
                    orderedTitles.append(norm)
                }
            }
        }

        for col in cloudCols {
            let norm = HistoryAndFavStore.normalizedFolderTitle(col.title)
            guard !norm.isEmpty else { continue }
            if cloudByTitle[norm] == nil {
                cloudByTitle[norm] = col
                if !orderedTitles.contains(norm) {
                    orderedTitles.append(norm)
                }
            }
        }

        let cloudEntries = activeCloudEntries
        return orderedTitles.map { norm in
            let localFolder = localByTitle[norm]
            let cloudCol = cloudByTitle[norm]
            let localCount: Int = {
                guard let lf = localFolder else { return 0 }
                return appState.historyAndFav.favorites.filter { $0.resolvedCollectionID == lf.id && !$0.resolvedIsCloudSynced }.count
            }()
            let cloudCount: Int = {
                guard let cc = cloudCol else { return 0 }
                let loadedCount = cloudEntries.filter { $0.collectionID == cc.id }.count
                return max(cc.itemNum, loadedCount)
            }()
            return MergedFavoriteFolderItem(
                key: norm,
                title: cloudCol?.title ?? localFolder?.title ?? norm,
                localFolder: localFolder,
                cloudCollection: cloudCol,
                localItemCount: localCount,
                cloudItemCount: cloudCount
            )
        }
    }

    private var selectedMergedFolder: MergedFavoriteFolderItem? {
        guard let selectedFolderKey else { return nil }
        return mergedFolders.first { $0.key == selectedFolderKey }
    }

    private var unifiedVisibleFavorites: [UnifiedFavoriteFeedItem] {
        let localFavs: [LocalFavoriteEntry]
        let cloudFavs: [CachedCloudFavoriteEntry]

        if let folder = selectedMergedFolder {
            if let lf = folder.localFolder {
                localFavs = appState.historyAndFav.favorites.filter {
                    $0.resolvedCollectionID == lf.id && !$0.resolvedIsCloudSynced
                }
            } else {
                localFavs = []
            }

            if let cc = folder.cloudCollection {
                let directCloud = activeCloudEntries.filter {
                    $0.collectionID == cc.id || HistoryAndFavStore.normalizedFolderTitle($0.collectionTitle) == folder.key
                }
                cloudFavs = directCloud
            } else {
                cloudFavs = []
            }
        } else {
            localFavs = appState.historyAndFav.favorites.filter { !$0.resolvedIsCloudSynced }
            cloudFavs = activeCloudEntries
        }

        var orderedFeedIDs: [String] = []
        var localByFeedID: [String: LocalFavoriteEntry] = [:]
        var cloudByFeedID: [String: [CachedCloudFavoriteEntry]] = [:]

        for entry in localFavs {
            if localByFeedID[entry.id] == nil {
                localByFeedID[entry.id] = entry
                orderedFeedIDs.append(entry.id)
            }
        }

        for entry in cloudFavs {
            let fid = entry.feed.id
            guard !fid.isEmpty else { continue }
            if cloudByFeedID[fid] == nil && localByFeedID[fid] == nil {
                orderedFeedIDs.append(fid)
            }
            cloudByFeedID[fid, default: []].append(entry)
        }

        for entry in appState.historyAndFav.favorites where entry.resolvedIsCloudSynced {
            if let folder = selectedMergedFolder {
                let matchesCloudID = folder.cloudCollection?.id == entry.resolvedCollectionID
                let matchesLocalID = folder.localFolder?.id == entry.resolvedCollectionID
                if !matchesCloudID && !matchesLocalID { continue }
            }
            if let feed = entry.feed {
                let fid = feed.id
                let synthetic = CachedCloudFavoriteEntry(
                    collectionID: entry.resolvedCollectionID,
                    collectionTitle: selectedMergedFolder?.title ?? "云端收藏夹",
                    feed: feed
                )
                if cloudByFeedID[fid] == nil && localByFeedID[fid] == nil {
                    orderedFeedIDs.append(fid)
                }
                if !(cloudByFeedID[fid]?.contains(where: { $0.collectionID == synthetic.collectionID }) ?? false) {
                    cloudByFeedID[fid, default: []].append(synthetic)
                }
            }
        }

        return orderedFeedIDs.map { fid in
            let lEntry = localByFeedID[fid]
            let cEntries = cloudByFeedID[fid] ?? []
            return UnifiedFavoriteFeedItem(
                feedID: fid,
                localEntry: lEntry,
                cloudEntry: cEntries.first,
                allCloudEntriesForFeed: cEntries
            )
        }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                folderSectionHeaderRow

                if !appState.settings.enableCloudFavoritesLoad && appState.accounts.isLoggedIn {
                    Text("已关闭云端收藏夹加载，仅显示本机收藏数据（可在设置开启）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                ForEach(mergedFolders) { folder in
                    SelectableCardWrapper(
                        isSelecting: isManagingFolders,
                        isSelected: selectedFolderKeys.contains(folder.key)
                    ) {
                        guard folder.isDeletable else {
                            appState.showToast("默认本机收藏夹不可删除")
                            return
                        }
                        if selectedFolderKeys.contains(folder.key) {
                            selectedFolderKeys.remove(folder.key)
                        } else {
                            selectedFolderKeys.insert(folder.key)
                        }
                    } content: {
                        mergedFolderCard(folder)
                    }
                }

                itemsSectionHeaderRow

                let visibleItems = unifiedVisibleFavorites
                if visibleItems.isEmpty {
                    if isSyncingCloud {
                        ProgressView("正在同步云端收藏…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        Text(selectedMergedFolder == nil ? "暂无收藏动态" : "该收藏夹暂无动态")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .c001CardStyle(cornerRadius: 20)
                            .padding(.horizontal, 12)
                    }
                } else {
                    ForEach(visibleItems) { item in
                        SelectableCardWrapper(
                            isSelecting: isSelectingItems,
                            isSelected: selectedItemIDs.contains(item.feedID)
                        ) {
                            if selectedItemIDs.contains(item.feedID) {
                                selectedItemIDs.remove(item.feedID)
                            } else {
                                selectedItemIDs.insert(item.feedID)
                            }
                        } content: {
                            favoriteFeedItemRow(item)
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.bottom, (isSelectingItems || isManagingFolders) ? 88 : 32)
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
                Button {
                    newFolderLocation = (appState.accounts.isLoggedIn && appState.settings.defaultFavoriteTarget == .cloud) ? .cloud : .local
                    showCreateFolderSheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("新建收藏夹")

                if !unifiedVisibleFavorites.isEmpty && !isManagingFolders {
                    Button(isSelectingItems ? "完成" : "多选") {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelectingItems.toggle()
                            if !isSelectingItems { selectedItemIDs.removeAll() }
                        }
                    }
                }

                Menu {
                    Button {
                        newFolderLocation = (appState.accounts.isLoggedIn && appState.settings.defaultFavoriteTarget == .cloud) ? .cloud : .local
                        showCreateFolderSheet = true
                    } label: {
                        Label("新建收藏夹…", systemImage: "folder.badge.plus")
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isSelectingItems = false
                            selectedItemIDs.removeAll()
                            isManagingFolders.toggle()
                            if !isManagingFolders { selectedFolderKeys.removeAll() }
                        }
                    } label: {
                        Label(isManagingFolders ? "退出收藏夹管理" : "批量管理收藏夹", systemImage: "folder.badge.gearshape")
                    }

                    if appState.settings.enableCloudFavoritesLoad && appState.accounts.isLoggedIn {
                        Button {
                            Task { await syncCloudFavorites(force: true) }
                        } label: {
                            Label("立即同步云端收藏", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    Divider()

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
        .sheet(isPresented: $showCreateFolderSheet) {
            createFolderSheetView
        }
        .safeAreaInset(edge: .bottom) {
            if isManagingFolders {
                let deletableKeys = Set(mergedFolders.filter(\.isDeletable).map(\.key))
                let allSelected = !deletableKeys.isEmpty && selectedFolderKeys.isSuperset(of: deletableKeys)
                BatchSelectionBottomBar(
                    selectedCount: selectedFolderKeys.count,
                    allSelected: allSelected,
                    deleteLabel: "删除收藏夹",
                    isBusy: isBatchDeleting,
                    onToggleSelectAll: {
                        if allSelected {
                            selectedFolderKeys.removeAll()
                        } else {
                            selectedFolderKeys = deletableKeys
                        }
                    },
                    onDelete: {
                        Task { await deleteSelectedFolders() }
                    }
                )
            } else if isSelectingItems {
                let allFeedIDs = Set(unifiedVisibleFavorites.map(\.feedID))
                let allSelected = !allFeedIDs.isEmpty && selectedItemIDs.isSuperset(of: allFeedIDs)
                BatchSelectionBottomBar(
                    selectedCount: selectedItemIDs.count,
                    allSelected: allSelected,
                    deleteLabel: "删除收藏",
                    isBusy: isBatchDeleting,
                    onToggleSelectAll: {
                        if allSelected {
                            selectedItemIDs.removeAll()
                        } else {
                            selectedItemIDs = allFeedIDs
                        }
                    },
                    onDelete: {
                        Task { await deleteSelectedFavoriteItems() }
                    }
                )
            }
        }
        .task(id: "\(appState.sessionVersion)|\(appState.settings.enableCloudFavoritesLoad)") {
            await syncCloudFavorites(force: false)
        }
    }

    private var folderSectionHeaderRow: some View {
        HStack(spacing: 12) {
            sectionHeader("收藏夹列表（同名本地与云端自动合并）")
            Spacer()
            if isSyncingCloud {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                newFolderLocation = (appState.accounts.isLoggedIn && appState.settings.defaultFavoriteTarget == .cloud) ? .cloud : .local
                showCreateFolderSheet = true
            } label: {
                Label("新建", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            if mergedFolders.contains(where: \.isDeletable) {
                Button(isManagingFolders ? "完成" : "管理") {
                    withAnimation(.snappy(duration: 0.2)) {
                        isSelectingItems = false
                        selectedItemIDs.removeAll()
                        isManagingFolders.toggle()
                        if !isManagingFolders { selectedFolderKeys.removeAll() }
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(isManagingFolders ? Color.accentColor : Color.secondary)
            }
        }
        .padding(.trailing, 16)
    }

    private var itemsSectionHeaderRow: some View {
        HStack {
            if let folder = selectedMergedFolder {
                sectionHeader("「\(folder.title)」收藏内容")
            } else {
                sectionHeader("全部收藏内容")
            }
            Spacer()
            if selectedFolderKey != nil {
                Button("查看全部") {
                    withAnimation(.snappy) { selectedFolderKey = nil }
                }
                .font(.caption.weight(.medium))
                .padding(.trailing, 16)
            }
        }
    }

    @ViewBuilder
    private func mergedFolderCard(_ folder: MergedFavoriteFolderItem) -> some View {
        let isSelected = selectedFolderKey == folder.key
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    selectedFolderKey = isSelected ? nil : folder.key
                }
                if let col = folder.cloudCollection {
                    Task { await loadCloudCollectionItems(col, force: false) }
                }
            } label: {
                HStack(spacing: 12) {
                    if !folder.logoURL.isEmpty {
                        RemoteImageView(url: folder.logoURL, maxPixelSize: 132, contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill((folder.hasCloud ? Color.blue : Color.accentColor).opacity(0.14))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: folder.hasCloud && folder.hasLocal ? "folder.fill.badge.person.crop" : (folder.hasCloud ? "icloud.fill" : "bookmark.fill"))
                                    .foregroundStyle(folder.hasCloud ? Color.blue : Color.accentColor)
                            }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(folder.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if folder.hasLocal {
                                SourceOriginBadge(isCloud: false)
                            }
                            if folder.hasCloud {
                                SourceOriginBadge(isCloud: true)
                            }
                        }
                        Text(folder.subtitleText + (isSelected ? " · 当前筛选中" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if let col = folder.cloudCollection {
                Button {
                    appState.push(.collection(id: col.id, initialTitle: col.title))
                } label: {
                    Image(systemName: isSelected ? "line.3.horizontal.decrease.circle.fill" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            } else if isSelected {
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
        .contextMenu {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    selectedFolderKey = isSelected ? nil : folder.key
                }
                if let col = folder.cloudCollection {
                    Task { await loadCloudCollectionItems(col, force: true) }
                }
            } label: {
                Label(isSelected ? "取消筛选此收藏夹" : "筛选此收藏夹内容", systemImage: "line.3.horizontal.decrease.circle")
            }

            if let col = folder.cloudCollection {
                Button {
                    appState.push(.collection(id: col.id, initialTitle: col.title))
                } label: {
                    Label("打开云端收藏夹详情页", systemImage: "arrow.up.right.square")
                }
            }

            if folder.isDeletable {
                Divider()
                if let lf = folder.localFolder, lf.id != HistoryAndFavStore.defaultFolderID, folder.hasCloud {
                    Button(role: .destructive) {
                        appState.historyAndFav.deleteFolder(id: lf.id)
                        appState.showToast("已删除本机同名收藏夹")
                    } label: {
                        Label("仅删除本机收藏夹", systemImage: "trash")
                    }
                }
                if let col = folder.cloudCollection, folder.hasLocal {
                    Button(role: .destructive) {
                        Task { await deleteFolders([folder], deleteLocal: false, deleteCloud: true) }
                    } label: {
                        Label("仅删除云端收藏夹", systemImage: "icloud.slash")
                    }
                }
                Button(role: .destructive) {
                    Task { await deleteFolders([folder], deleteLocal: true, deleteCloud: true) }
                } label: {
                    Label(folder.hasLocal && folder.hasCloud ? "同时删除本机与云端收藏夹" : "删除收藏夹", systemImage: "trash.fill")
                }
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func favoriteFeedItemRow(_ item: UnifiedFavoriteFeedItem) -> some View {
        if let cloudEntry = item.cloudEntry, !item.isLocal {
            FeedRowView(
                feed: cloudEntry.feed,
                originBadgeIsCloud: true,
                contextDeleteTitle: "取消云端收藏",
                onContextDelete: {
                    Task { await removeCloudFavorites(item.allCloudEntriesForFeed) }
                }
            )
        } else if let localEntry = item.localEntry {
            StoredFeedCardRow(
                feedID: localEntry.id,
                snapshot: localEntry.feed,
                fallbackTitle: localEntry.title,
                fallbackPreview: localEntry.preview,
                fallbackUsername: localEntry.username,
                fallbackAvatar: localEntry.avatar,
                fallbackDate: localEntry.savedAt,
                badgeIsCloud: item.isCloud && !item.isLocal,
                deleteTitle: item.isCloud ? "同时移除本机与云端收藏" : "取消本机收藏",
                onDelete: {
                    appState.historyAndFav.removeFavorite(id: localEntry.id)
                    if !item.allCloudEntriesForFeed.isEmpty {
                        Task { await removeCloudFavorites(item.allCloudEntriesForFeed) }
                    }
                }
            )
        }
    }

    private var createFolderSheetView: some View {
        NavigationStack {
            Form {
                Section("收藏夹信息") {
                    TextField("收藏夹名称（必填）", text: $newFolderTitle)
                    TextField("简介（可选）", text: $newFolderDescription)
                }

                Section {
                    Picker("创建位置", selection: $newFolderLocation) {
                        Text("本机收藏夹").tag(NewFolderLocationMode.local)
                        if appState.accounts.isLoggedIn {
                            Text("云端收藏夹").tag(NewFolderLocationMode.cloud)
                            Text("本机 + 云端同名").tag(NewFolderLocationMode.both)
                        }
                    }
                    .pickerStyle(.segmented)

                    if newFolderLocation != .local {
                        Toggle("公开云端收藏夹", isOn: $newFolderIsOpen)
                    }
                } header: {
                    Text("存储位置")
                } footer: {
                    Text("同名本机收藏夹与云端收藏夹会在列表中自动合并为一个统一入口，并同时展示本地与云端角标。")
                }
            }
            .navigationTitle("新建收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showCreateFolderSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await createNewFolderAction() }
                    } label: {
                        if isCreatingFolder {
                            ProgressView()
                        } else {
                            Text("创建")
                        }
                    }
                    .disabled(newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingFolder)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createNewFolderAction() async {
        let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = newFolderDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreatingFolder else { return }
        isCreatingFolder = true
        defer { isCreatingFolder = false }

        var createdLocal = false
        var createdCloud = false

        if newFolderLocation == .local || newFolderLocation == .both {
            _ = appState.historyAndFav.createFolder(title: title)
            createdLocal = true
        }

        if (newFolderLocation == .cloud || newFolderLocation == .both) && appState.accounts.isLoggedIn {
            do {
                if let created = try await API.createCollection(title: title, description: desc, isOpen: newFolderIsOpen) {
                    var cols = appState.historyAndFav.cachedCloudCollections
                    if !cols.contains(where: { $0.id == created.id }) {
                        cols.insert(created, at: 0)
                    }
                    appState.historyAndFav.updateCloudCache(collections: cols, entries: appState.historyAndFav.cachedCloudEntries)
                    createdCloud = true
                } else {
                    await syncCloudFavorites(force: true)
                    createdCloud = true
                }
            } catch {
                _ = await appState.handleAPIError(error)
            }
        }

        newFolderTitle = ""
        newFolderDescription = ""
        showCreateFolderSheet = false
        selectedFolderKey = HistoryAndFavStore.normalizedFolderTitle(title)

        if createdLocal && createdCloud {
            appState.showToast("已创建本机与云端同名收藏夹")
        } else if createdCloud {
            appState.showToast("已创建云端收藏夹")
        } else if createdLocal {
            appState.showToast("已创建本机收藏夹")
        }
    }

    private func deleteSelectedFolders() async {
        let targets = mergedFolders.filter { selectedFolderKeys.contains($0.key) && $0.isDeletable }
        guard !targets.isEmpty, !isBatchDeleting else { return }
        isBatchDeleting = true
        defer { isBatchDeleting = false }

        await deleteFolders(targets, deleteLocal: true, deleteCloud: true)
        selectedFolderKeys.removeAll()
        isManagingFolders = false
    }

    private func deleteFolders(_ targets: [MergedFavoriteFolderItem], deleteLocal: Bool, deleteCloud: Bool) async {
        var deletedCount = 0
        for folder in targets {
            var didDeleteThis = false
            if deleteLocal, let lf = folder.localFolder, lf.id != HistoryAndFavStore.defaultFolderID {
                appState.historyAndFav.deleteFolder(id: lf.id)
                didDeleteThis = true
            }
            if deleteCloud, let col = folder.cloudCollection {
                do {
                    try await API.deleteCollection(id: col.id)
                    appState.historyAndFav.removeCloudCachedCollection(id: col.id)
                    didDeleteThis = true
                } catch {
                    _ = await appState.handleAPIError(error)
                }
            }
            if didDeleteThis {
                deletedCount += 1
                if selectedFolderKey == folder.key {
                    selectedFolderKey = nil
                }
            }
        }
        if deletedCount > 0 {
            appState.showToast("已删除 \(deletedCount) 个收藏夹")
        }
    }

    private func deleteSelectedFavoriteItems() async {
        guard !selectedItemIDs.isEmpty, !isBatchDeleting else { return }
        isBatchDeleting = true
        defer { isBatchDeleting = false }

        let targets = unifiedVisibleFavorites.filter { selectedItemIDs.contains($0.feedID) }
        let localIDs = Set(targets.compactMap { $0.localEntry?.id })
        let cloudToDelete = targets.flatMap(\.allCloudEntriesForFeed)

        if !localIDs.isEmpty {
            appState.historyAndFav.removeFavorites(ids: localIDs)
        }
        if !cloudToDelete.isEmpty {
            await removeCloudFavorites(cloudToDelete)
        }

        let removedCount = targets.count
        selectedItemIDs.removeAll()
        isSelectingItems = false
        if removedCount > 0 {
            appState.showToast("已删除 \(removedCount) 条收藏")
        }
    }

    private func removeCloudFavorites(_ entries: [CachedCloudFavoriteEntry]) async {
        var removedIDs = Set<String>()
        var removedFeedIDs = Set<String>()
        for entry in entries {
            do {
                try await API.collectFeedToCollection(
                    feedID: entry.feed.id,
                    addCollectionIDs: [],
                    cancelCollectionIDs: [entry.collectionID]
                )
                removedIDs.insert(entry.id)
                removedFeedIDs.insert(entry.feed.id)
            } catch {
                _ = await appState.handleAPIError(error)
            }
        }
        if !removedIDs.isEmpty {
            appState.historyAndFav.removeCloudCachedEntries(ids: removedIDs)
            for fid in removedFeedIDs {
                if let entry = appState.historyAndFav.favorites.first(where: { $0.id == fid && $0.resolvedIsCloudSynced }) {
                    appState.historyAndFav.removeFavorite(id: entry.id)
                }
            }
            appState.showToast("已取消云端收藏")
        }
    }

    private func syncCloudFavorites(force: Bool) async {
        guard appState.settings.enableCloudFavoritesLoad,
              appState.accounts.isLoggedIn else {
            return
        }
        if !force && !appState.historyAndFav.cachedCloudCollections.isEmpty && !appState.historyAndFav.cachedCloudEntries.isEmpty {
            return
        }
        isSyncingCloud = true
        defer { isSyncingCloud = false }

        let uid = appState.accounts.activeUID ?? ""
        do {
            let cols = try await API.collectionList(uid: uid, page: 1)
            let collected = await withTaskGroup(of: [CachedCloudFavoriteEntry].self) { group in
                for col in cols.prefix(12) {
                    group.addTask {
                        let rows = (try? await API.collectionItems(id: col.id, page: 1)) ?? []
                        return rows.compactMap { row -> CachedCloudFavoriteEntry? in
                            if case let .feed(feed) = row {
                                return CachedCloudFavoriteEntry(collectionID: col.id, collectionTitle: col.title, feed: feed)
                            }
                            return nil
                        }
                    }
                }
                var merged: [CachedCloudFavoriteEntry] = []
                for await batch in group {
                    merged.append(contentsOf: batch)
                }
                return merged
            }
            if !cols.isEmpty || force {
                appState.historyAndFav.updateCloudCache(collections: cols, entries: collected)
            }
        } catch {
            if appState.historyAndFav.cachedCloudCollections.isEmpty {
                _ = await appState.handleAPIError(error)
            }
        }
    }

    private func loadCloudCollectionItems(_ col: CollectionItem, force: Bool) async {
        let alreadyLoaded = appState.historyAndFav.cachedCloudEntries.contains { $0.collectionID == col.id }
        if !force && alreadyLoaded { return }
        guard let rows = try? await API.collectionItems(id: col.id, page: 1) else { return }
        let entries = rows.compactMap { row -> CachedCloudFavoriteEntry? in
            if case let .feed(feed) = row {
                return CachedCloudFavoriteEntry(collectionID: col.id, collectionTitle: col.title, feed: feed)
            }
            return nil
        }
        if !entries.isEmpty {
            appState.historyAndFav.appendCloudCachedEntries(entries)
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
                    .padding(.top, 2)
                    .padding(.bottom, 42)
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
