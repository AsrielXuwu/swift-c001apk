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
            let chronological = fetched
                .reversed()
                .filter { !($0.isLongTimeFlag && $0.message.isEmpty && $0.messagePic.isEmpty) }
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
        defer { resolvingIDs.remove(message.id) }
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var chatSeed = UUID().uuidString
    @State private var viewModel: ChatThreadViewModel
    @State private var draftText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var lastObservedTailID: String?
    @State private var showEmojiPanel = false
    @FocusState private var isComposerFocused: Bool

    private let bottomAnchorID = "chat-bottom-anchor"

    public init(ukey: String, peerUID: String, peerName: String, peerAvatar: String) {
        self.ukey = ukey
        self.peerUID = peerUID
        self.peerName = peerName
        self.peerAvatar = peerAvatar
        self._viewModel = State(initialValue: ChatThreadViewModel(ukey: ukey, peerUID: peerUID))
    }

    private var visibleMessages: [ChatMessage] {
        viewModel.messages.filter { !($0.isLongTimeFlag && $0.message.isEmpty && $0.messagePic.isEmpty) }
    }

    public var body: some View {
        let items = visibleMessages
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.hasMore {
                        Button("加载更早消息") {
                            Task { await viewModel.loadOlder(appState: appState) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                    }

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, msg in
                        let prev = index > 0 ? items[index - 1] : nil
                        let next = index + 1 < items.count ? items[index + 1] : nil
                        let showsTimeAbove = shouldShowTimestampHeader(current: msg, previous: prev)
                        let nextShowsTimeAbove = next.map { shouldShowTimestampHeader(current: $0, previous: msg) } ?? false
                        let isFirstInCluster = showsTimeAbove || prev?.fromUID != msg.fromUID
                        let isLastInCluster = nextShowsTimeAbove || next?.fromUID != msg.fromUID

                        VStack(spacing: 6) {
                            if showsTimeAbove {
                                timestampHeader(for: msg)
                            }
                            messageRow(msg, isLastInCluster: isLastInCluster)
                        }
                        .padding(.top, index == 0 ? 4 : (showsTimeAbove ? 14 : (isFirstInCluster ? 10 : 3)))
                        .id(msg.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: items.last?.id) { _, lastID in
                guard let lastID, lastID != lastObservedTailID else { return }
                let shouldAnimate = (lastObservedTailID != nil)
                lastObservedTailID = lastID
                if shouldAnimate {
                    withAnimation(.snappy(duration: 0.24)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .onChange(of: isComposerFocused) { _, focused in
                if focused {
                    showEmojiPanel = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 60_000_000)
                        withAnimation(.snappy(duration: 0.24)) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: showEmojiPanel) { _, shown in
                if shown {
                    isComposerFocused = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 60_000_000)
                        withAnimation(.snappy(duration: 0.24)) {
                            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
        .c001PageBackground()
        .navigationTitle(peerName.isEmpty ? "私信" : peerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.push(.user(uid: peerUID, initialUsername: peerName, initialAvatar: peerAvatar))
                } label: {
                    AvatarView(url: peerAvatar, size: 28)
                }
            }
        }
        .task {
            await viewModel.loadInitial(appState: appState)
        }
        .environment(\.openURL, OpenURLAction { url in
            appState.openRawLink(url.absoluteString)
            return .handled
        })
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

    private func shouldShowTimestampHeader(current: ChatMessage, previous: ChatMessage?) -> Bool {
        if current.isLongTimeFlag { return true }
        guard let previous else { return current.dateline != nil }
        guard let curDate = current.dateline, let prevDate = previous.dateline else { return false }
        return abs(curDate.timeIntervalSince(prevDate)) >= 300
    }

    @ViewBuilder
    private func timestampHeader(for msg: ChatMessage) -> some View {
        let label = Formatting.chatTimestamp(msg.dateline)
        if !label.isEmpty {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: ChatMessage, isLastInCluster: Bool) -> some View {
        let isMine = msg.fromUID == appState.accounts.activeUID
        let picURL = msg.messagePic.isEmpty ? (viewModel.resolvedImages[msg.id]?.absoluteString ?? "") : msg.messagePic
        let hasText = !msg.message.isEmpty && msg.message != "[图片]"
        let bubbleShape = IMessageBubbleShape(isMine: isMine, showTail: isLastInCluster)
        let incomingFill: Color = colorScheme == .dark
            ? Color(.tertiarySystemGroupedBackground)
            : Color(uiColor: .systemGray5)

        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 56)
            } else if isLastInCluster {
                Button {
                    appState.push(.user(uid: peerUID, initialUsername: peerName, initialAvatar: peerAvatar))
                } label: {
                    AvatarView(url: msg.fromAvatar.isEmpty ? peerAvatar : msg.fromAvatar, size: 28)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 28, height: 1)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !picURL.isEmpty {
                    let chatPicPrefix = "chat-pic-\(chatSeed)-\(msg.id)"
                    Button {
                        appState.openMedia([FeedMedia(sourceUrl: picURL)], at: 0, sourcePrefix: chatPicPrefix)
                    } label: {
                        RemoteImageView(url: picURL, maxPixelSize: 600)
                            .frame(maxWidth: 228, maxHeight: 228)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .applyZoomSource(id: "\(chatPicPrefix)-0", in: zoomNamespace, cornerRadius: 18)
                    }
                    .buttonStyle(.plain)
                } else if msg.message.contains("[图片]") || msg.message.isEmpty {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .task { await viewModel.resolveImageIfNeeded(for: msg) }
                }

                if hasText {
                    EmojiBundleStore.richEmojiText(
                        msg.message,
                        emojiPointSize: 20,
                        showEmoji: appState.settings.showEmoji
                    )
                    .font(.body)
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .tint(isMine ? Color.white : Color.accentColor)
                    .padding(.top, 9)
                    .padding(.bottom, 9)
                    .padding(.leading, isMine ? 13 : 18)
                    .padding(.trailing, isMine ? 18 : 13)
                    .background {
                        if isMine {
                            bubbleShape.fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.06, green: 0.53, blue: 1.0),
                                        Color(red: 0.0, green: 0.45, blue: 0.98)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        } else {
                            bubbleShape
                                .fill(incomingFill)
                                .overlay {
                                    bubbleShape.stroke(
                                        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04),
                                        lineWidth: 0.5
                                    )
                                }
                        }
                    }
                    .contentShape(.contextMenuPreview, bubbleShape)
                }

                if case .sending = msg.deliveryState {
                    Text("正在发送…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else if case let .failed(reason) = msg.deliveryState {
                    Text("发送失败：\(reason)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
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

            if !isMine {
                Spacer(minLength: 48)
            }
        }
    }

    private var composerBar: some View {
        let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 8) {
            GlassEffectContainer(spacing: 8) {
                HStack(alignment: .bottom, spacing: 8) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.body.weight(.semibold))
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(.primary)
                    }

                    Button {
                        if showEmojiPanel {
                            showEmojiPanel = false
                            isComposerFocused = true
                        } else {
                            isComposerFocused = false
                            showEmojiPanel = true
                        }
                    } label: {
                        Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling")
                            .font(.body.weight(.semibold))
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(showEmojiPanel ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showEmojiPanel ? "切换键盘" : "选择表情")

                    TextField("信息", text: $draftText, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isComposerFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 38)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Button {
                        let text = draftText
                        draftText = ""
                        Task { await viewModel.sendText(text, appState: appState) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .frame(width: 38, height: 38)
                            .background(
                                canSend ? Color(red: 0.0, green: 0.478, blue: 1.0) : Color.clear,
                                in: Circle()
                            )
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(canSend ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }

            if showEmojiPanel {
                EmojiPickerView { name in
                    draftText += name
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.22), value: showEmojiPanel)
    }
}

private struct IMessageBubbleShape: Shape {
    let isMine: Bool
    let showTail: Bool

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let tailWidth: CGFloat = 5
        guard width > tailWidth + 12, height > 16 else {
            return RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
        }

        if !showTail {
            let insetRect = CGRect(
                x: isMine ? 0 : tailWidth,
                y: 0,
                width: width - tailWidth,
                height: height
            )
            return RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: insetRect)
        }

        let bodyRight = width - tailWidth
        let radius = min(18, min(bodyRight, height) * 0.45)

        var path = Path()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: bodyRight - radius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: bodyRight, y: radius),
            control: CGPoint(x: bodyRight, y: 0)
        )
        path.addLine(to: CGPoint(x: bodyRight, y: max(radius, height - 13)))
        path.addCurve(
            to: CGPoint(x: width, y: height),
            control1: CGPoint(x: bodyRight, y: height - 5),
            control2: CGPoint(x: width - 1.5, y: height - 1)
        )
        path.addCurve(
            to: CGPoint(x: bodyRight - 6, y: height - 2.5),
            control1: CGPoint(x: width - 3, y: height),
            control2: CGPoint(x: bodyRight - 2, y: height - 0.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: bodyRight - min(18, bodyRight * 0.4), y: height),
            control: CGPoint(x: bodyRight - 10, y: height)
        )
        path.addLine(to: CGPoint(x: radius, y: height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: height - radius),
            control: CGPoint(x: 0, y: height)
        )
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(
            to: CGPoint(x: radius, y: 0),
            control: CGPoint(x: 0, y: 0)
        )
        path.closeSubpath()

        if isMine {
            return path
        }
        let mirrored = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -width, y: 0)
        return path.applying(mirrored)
    }
}
