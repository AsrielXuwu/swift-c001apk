import CoolapkKit
import SwiftUI

public struct CollectionPickerSheet: View {
    public let feed: FeedItem

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var cloudCollections: [CollectionItem] = []
    @State private var isLoadingCloud = false
    @State private var newFolderName = ""
    @State private var isCreatingFolder = false
    @State private var isSaving = false

    public init(feed: FeedItem) {
        self.feed = feed
    }

    private var canUseCloudCollections: Bool {
        appState.accounts.isLoggedIn && appState.settings.enableCloudFavoritesLoad
    }

    private var isCloudWriteEnabled: Bool {
        appState.accounts.isLoggedIn && appState.settings.defaultFavoriteTarget == .cloud
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("新建收藏夹名称…", text: $newFolderName)
                            .textInputAutocapitalization(.never)
                        Button {
                            Task { await createNewFolder() }
                        } label: {
                            if isCreatingFolder {
                                ProgressView()
                            } else {
                                Text("创建")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingFolder)
                    }
                } header: {
                    Text(isCloudWriteEnabled ? "当前模式：同步到云端" : "当前模式：仅保存到本机（防风控）")
                }

                Section("本机收藏夹") {
                    ForEach(appState.historyAndFav.folders.filter { !$0.isCloudLinked }) { folder in
                        let selected = appState.historyAndFav.isLocallyFavorited(feedID: feed.id, inLocalFolderID: folder.id)
                        folderRow(
                            id: folder.id,
                            title: folder.title,
                            subtitle: "\(appState.historyAndFav.count(inFolder: folder.id)) 条动态",
                            isCloud: false,
                            isSelected: selected
                        ) {
                            saveToFolder(id: folder.id, title: folder.title, isCloudFolder: false)
                        }
                    }
                }

                if canUseCloudCollections {
                    Section {
                        if isLoadingCloud && cloudCollections.isEmpty {
                            HStack {
                                ProgressView()
                                Text("正在加载云端收藏夹…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else if cloudCollections.isEmpty {
                            Text("暂无云端收藏夹")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(cloudCollections) { col in
                                let selected: Bool = {
                                    if isCloudWriteEnabled {
                                        return appState.historyAndFav.isCloudFavorited(feedID: feed.id, inCloudCollection: col)
                                    } else {
                                        let norm = HistoryAndFavStore.normalizedFolderTitle(col.title)
                                        if let matchingLocal = appState.historyAndFav.folders.first(where: {
                                            !$0.isCloudLinked && HistoryAndFavStore.normalizedFolderTitle($0.title) == norm
                                        }) {
                                            return appState.historyAndFav.isLocallyFavorited(feedID: feed.id, inLocalFolderID: matchingLocal.id)
                                        }
                                        return false
                                    }
                                }()
                                folderRow(
                                    id: col.id,
                                    title: col.title,
                                    subtitle: "\(col.itemNum) 项内容" + (isCloudWriteEnabled ? "" : " · 将保存至本机同名列表"),
                                    isCloud: true,
                                    isSelected: selected
                                ) {
                                    saveToFolder(id: col.id, title: col.title, isCloudFolder: true)
                                }
                            }
                        }
                    } header: {
                        Text("云端收藏夹")
                    }
                }

                if appState.historyAndFav.isLocallyFavorited(id: feed.id) || feed.isFavorited {
                    Section {
                        Button("从当前收藏移除", role: .destructive) {
                            Task { await removeFavorite() }
                        }
                    }
                }
            }
            .navigationTitle("选择收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await loadCloudCollections()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func folderRow(
        id: String,
        title: String,
        subtitle: String,
        isCloud: Bool,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        SourceOriginBadge(isCloud: isCloud)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(isSaving)
    }

    private func loadCloudCollections() async {
        guard canUseCloudCollections, let uid = appState.accounts.activeUID else { return }
        isLoadingCloud = true
        defer { isLoadingCloud = false }
        cloudCollections = (try? await API.collectionList(uid: uid, feedID: feed.id, page: 1)) ?? []
    }

    private func createNewFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isCreatingFolder = true
        defer { isCreatingFolder = false }

        if isCloudWriteEnabled {
            if let created = try? await API.createCollection(title: name) {
                cloudCollections.insert(created, at: 0)
                newFolderName = ""
                appState.showToast("已创建云端收藏夹「\(created.title)」")
                return
            }
        }
        _ = appState.historyAndFav.createFolder(title: name)
        newFolderName = ""
        appState.showToast("已创建本机收藏夹「\(name)」")
    }

    private func saveToFolder(id: String, title: String, isCloudFolder: Bool) {
        if !isCloudFolder {
            appState.historyAndFav.saveFavorite(feed, folderID: id, folderTitle: title, isCloudSynced: false)
            appState.showToast("已保存到本机「\(title)」")
            dismiss()
            return
        }

        if isCloudWriteEnabled {
            isSaving = true
            Task {
                defer { isSaving = false }
                do {
                    try await API.collectFeedToCollection(feedID: feed.id, addCollectionIDs: [id])
                    appState.historyAndFav.saveFavorite(feed, folderID: id, folderTitle: title, isCloudSynced: true)
                    appState.showToast("已同步收藏到云端「\(title)」")
                    dismiss()
                } catch {
                    _ = await appState.handleAPIError(error)
                }
            }
        } else {
            let localFolder = appState.historyAndFav.createFolder(title: title, linkedCloudID: nil)
            appState.historyAndFav.saveFavorite(feed, folderID: localFolder.id, folderTitle: localFolder.title, isCloudSynced: false)
            appState.showToast("已保存到本机「\(localFolder.title)」")
            dismiss()
        }
    }

    private func removeFavorite() async {
        appState.historyAndFav.removeFavorite(id: feed.id)
        if isCloudWriteEnabled && feed.isFavorited {
            try? await API.collectFeed(id: feed.id, collected: false)
        }
        appState.showToast("已取消收藏")
        dismiss()
    }
}

public struct SourceOriginBadge: View {
    public let isCloud: Bool

    public init(isCloud: Bool) {
        self.isCloud = isCloud
    }

    public var body: some View {
        Text(isCloud ? "云端" : "本地")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isCloud ? Color.blue : Color.green).opacity(0.15), in: Capsule())
            .foregroundStyle(isCloud ? Color.blue : Color.green)
    }
}
