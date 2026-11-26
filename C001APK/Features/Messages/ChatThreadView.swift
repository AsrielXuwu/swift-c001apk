import CoolapkKit
import PhotosUI
import SwiftUI
import UIKit

@MainActor
@Observable
public final class ChatThreadViewModel {
    public let ukey: String
    public let peerUID: String

    public private(set) var messages: [ChatMessage] = []
    public private(set) var resolvedImages: [String: URL] = [:]
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var hasMore = true

    private var currentPage = 1
    private var resolvingIDs: Set<String> = []

    public init(ukey: String, peerUID: String) {
        self.ukey = ukey
        self.peerUID = peerUID
    }

    public func loadInitial(appState: AppState) async {
        currentPage = 1
        hasMore = true
        isLoading = true
        defer { isLoading = false }
        await fetch(page: 1, append: false, appState: appState)
    }

    public func loadOlder(appState: AppState) async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetch(page: currentPage + 1, append: true, appState: appState)
    }

    private func fetch(page: Int, append: Bool, appState: AppState) async {
        do {
            let fetched = try await API.chatMessages(ukey: ukey, peerUID: peerUID, page: page)
            let chronological = fetched.reversed()
            if append {
                var seen = Set(messages.map(\.id))
                let unique = chronological.filter { seen.insert($0.id).inserted }
                messages.insert(contentsOf: unique, at: 0)
                hasMore = !unique.isEmpty
            } else {
                messages = Array(chronological)
                hasMore = !fetched.isEmpty
            }
            currentPage = page
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    public func resolveImageIfNeeded(for message: ChatMessage) async {
        guard message.messagePic.isEmpty,
              resolvedImages[message.id] == nil,
              resolvingIDs.insert(message.id).inserted else { return }
        if let resolved = try? await CoolapkClient.shared.resolveMessageImageURL(id: message.id) {
            resolvedImages[message.id] = resolved
        }
    }

    public func sendText(_ text: String, appState: AppState) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let localID = "local-\(UUID().uuidString)"
        let myUID = appState.accounts.activeUID ?? ""
        let myAvatar = appState.accounts.activeAccount?.avatar ?? ""

        let local = ChatMessage(
            id: localID,
            fromUID: myUID,
            fromAvatar: myAvatar,
            message: trimmed,
            deliveryState: .sending
        )
        messages.append(local)

        do {
            let sent = try await API.sendChatMessage(uid: peerUID, text: trimmed)
            replaceLocal(localID: localID, with: sent.first)
        } catch {
            markFailed(localID: localID, error: error.localizedDescription)
            _ = await appState.handleAPIError(error)
        }
    }

    public func sendImageData(_ data: Data, filename: String, mimeType: String, resolution: String, appState: AppState) async {
        let localID = "local-\(UUID().uuidString)"
        let myUID = appState.accounts.activeUID ?? ""
        let myAvatar = appState.accounts.activeAccount?.avatar ?? ""

        let local = ChatMessage(
            id: localID,
            fromUID: myUID,
            fromAvatar: myAvatar,
            message: "[图片]",
            deliveryState: .sending
        )
        messages.append(local)

        do {
            let ossPath = try await CoolapkClient.shared.uploadChatImageToOSS(
                data: data,
                filename: filename,
                mimeType: mimeType,
                resolution: resolution,
                toUID: peerUID
            )
            let sent = try await API.sendChatMessage(uid: peerUID, text: "", picturePath: ossPath)
            replaceLocal(localID: localID, with: sent.first)
        } catch {
            markFailed(localID: localID, error: error.localizedDescription)
            _ = await appState.handleAPIError(error)
        }
    }

    public func deleteMessage(_ message: ChatMessage, appState: AppState) async {
        if message.id.hasPrefix("local-") {
            messages.removeAll { $0.id == message.id }
            return
        }
        do {
            try await API.deleteChatMessage(ukey: ukey, id: message.id)
            messages.removeAll { $0.id == message.id }
            appState.showToast("已删除消息")
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func replaceLocal(localID: String, with remote: ChatMessage?) {
        guard let idx = messages.firstIndex(where: { $0.id == localID }) else { return }
        if let remote {
            messages[idx] = remote
        } else {
            messages[idx].deliveryState = .sent
        }
    }

    private func markFailed(localID: String, error: String) {
        guard let idx = messages.firstIndex(where: { $0.id == localID }) else { return }
        messages[idx].deliveryState = .failed(error)
    }
}

public struct ChatThreadView: View {
    public let ukey: String
    public let peerUID: String
    public let peerName: String
    public let peerAvatar: String

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var chatSeed = UUID().uuidString
    @State private var viewModel: ChatThreadViewModel
    @State private var draftText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?

    public init(ukey: String, peerUID: String, peerName: String, peerAvatar: String) {
        self.ukey = ukey
        self.peerUID = peerUID
        self.peerName = peerName
        self.peerAvatar = peerAvatar
        self._viewModel = State(initialValue: ChatThreadViewModel(ukey: ukey, peerUID: peerUID))
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.hasMore {
                        Button("加载更早消息") {
                            Task { await viewModel.loadOlder(appState: appState) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    }

                    ForEach(viewModel.messages) { msg in
                        messageBubble(msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastID = viewModel.messages.last?.id {
                    withAnimation(.snappy) { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(peerName.isEmpty ? "私信" : peerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.push(.user(uid: peerUID))
                } label: {
                    AvatarView(url: peerAvatar, size: 28)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composerBar
        }
        .task {
            await viewModel.loadInitial(appState: appState)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.85) {
                    let res = "\(Int(image.size.width * image.scale))x\(Int(image.size.height * image.scale))"
                    await viewModel.sendImageData(
                        jpeg,
                        filename: "\(UUID().uuidString).jpg",
                        mimeType: "image/jpeg",
                        resolution: res,
                        appState: appState
                    )
                }
                selectedPhotoItem = nil
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ msg: ChatMessage) -> some View {
        if msg.isLongTimeFlag {
            Text(Formatting.relativeTime(msg.dateline))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            let isMine = msg.fromUID == appState.accounts.activeUID
            HStack(alignment: .bottom, spacing: 8) {
                if isMine { Spacer(minLength: 48) } else {
                    AvatarView(url: msg.fromAvatar.isEmpty ? peerAvatar : msg.fromAvatar, size: 32)
                }

                VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                    let picURL = msg.messagePic.isEmpty ? (viewModel.resolvedImages[msg.id]?.absoluteString ?? "") : msg.messagePic
                    if !picURL.isEmpty {
                        let chatPicPrefix = "chat-pic-\(chatSeed)-\(msg.id)"
                        Button {
                            appState.openMedia([FeedMedia(sourceUrl: picURL)], at: 0, sourcePrefix: chatPicPrefix)
                        } label: {
                            RemoteImageView(url: picURL, maxPixelSize: 600)
                                .frame(maxWidth: 220, maxHeight: 220)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .applyZoomSource(id: "\(chatPicPrefix)-0", in: zoomNamespace)
                        }
                        .buttonStyle(.plain)
                    } else if msg.message.contains("[图片]") || msg.message.isEmpty {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .task { await viewModel.resolveImageIfNeeded(for: msg) }
                    }

                    if !msg.message.isEmpty && msg.message != "[图片]" {
                        Text(FeedHTMLParser.plainText(msg.message))
                            .font(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                isMine ? Color.accentColor : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .foregroundStyle(isMine ? Color.white : Color.primary)
                    }

                    if case .sending = msg.deliveryState {
                        Text("发送中…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if case let .failed(reason) = msg.deliveryState {
                        Text("发送失败：\(reason)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .contextMenu {
                    if !msg.message.isEmpty {
                        Button {
                            UIPasteboard.general.string = FeedHTMLParser.plainText(msg.message)
                            appState.showToast("已复制")
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }
                    Button(role: .destructive) {
                        Task { await viewModel.deleteMessage(msg, appState: appState) }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }

                if !isMine { Spacer(minLength: 48) }
            }
        }
    }

    private var composerBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }

                TextField("发送私信…", text: $draftText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)

                Button {
                    let text = draftText
                    draftText = ""
                    Task { await viewModel.sendText(text, appState: appState) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(
                            draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.clear
                                : Color.accentColor.opacity(0.22),
                            in: Circle()
                        )
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(
                            draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary
                                : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
