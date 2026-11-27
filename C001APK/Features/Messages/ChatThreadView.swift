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
                withAnimation(.smooth(duration: 0.22)) {
                    messages.insert(contentsOf: unique, at: 0)
                }
                hasMore = !unique.isEmpty
            } else {
                withAnimation(.smooth(duration: 0.22)) {
                    messages = Array(chronological)
                }
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
            withAnimation(.smooth(duration: 0.2)) {
                resolvedImages[message.id] = resolved
            }
        }
    }

    public func sendText(_ text: String, appState: AppState) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let localID = "local-\(UUID().uuidString)"
        let myUID = appState.accounts.activeUID ?? ""
        let myAvatar = appState.currentUserProfile?.avatar ?? appState.accounts.activeAccount?.avatar ?? ""

        let local = ChatMessage(
            id: localID,
            fromUID: myUID,
            fromAvatar: myAvatar,
            message: trimmed,
            deliveryState: .sending
        )
        withAnimation(.snappy(duration: 0.22)) {
            messages.append(local)
        }

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
        let myAvatar = appState.currentUserProfile?.avatar ?? appState.accounts.activeAccount?.avatar ?? ""

        let local = ChatMessage(
            id: localID,
            fromUID: myUID,
            fromAvatar: myAvatar,
            message: "[图片]",
            deliveryState: .sending
        )
        withAnimation(.snappy(duration: 0.22)) {
            messages.append(local)
        }

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
            withAnimation(.snappy(duration: 0.2)) {
                messages.removeAll { $0.id == message.id }
            }
            return
        }
        do {
            try await API.deleteChatMessage(ukey: ukey, id: message.id)
            withAnimation(.snappy(duration: 0.2)) {
                messages.removeAll { $0.id == message.id }
            }
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
    @State private var keyboardEndMinY: CGFloat = 0
    @State private var containerGlobalMaxY: CGFloat = 0
    @State private var restingContainerMaxY: CGFloat = 0
    @State private var lastKnownKeyboardLift: CGFloat = 276
    @State private var isHoldingSlotForKeyboard = false
    @FocusState private var isComposerFocused: Bool

    private var currentKeyboardOverlap: CGFloat {
        guard keyboardEndMinY > 0, containerGlobalMaxY > keyboardEndMinY else { return 0 }
        let overlap = containerGlobalMaxY - keyboardEndMinY
        return overlap > 24 ? overlap : 0
    }

    private var currentSystemLift: CGFloat {
        guard restingContainerMaxY > 0, containerGlobalMaxY > 0, restingContainerMaxY > containerGlobalMaxY else { return 0 }
        return restingContainerMaxY - containerGlobalMaxY
    }

    private var activeBottomSlotHeight: CGFloat {
        let kbOverlap = currentKeyboardOverlap
        if showEmojiPanel || isHoldingSlotForKeyboard {
            if showEmojiPanel && kbOverlap > 40 {
                return 202 + kbOverlap
            }
            if showEmojiPanel && currentSystemLift > 40 {
                return 202
            }
            let targetLift = max(256, lastKnownKeyboardLift)
            let needed = max(0, targetLift - currentSystemLift)
            return max(kbOverlap, needed)
        }
        return kbOverlap
    }

    private let bottomAnchorID = "chat-bottom-anchor"

    public init(ukey: String, peerUID: String, peerName: String, peerAvatar: String) {
        self.ukey = ukey
        self.peerUID = peerUID
        self.peerName = peerName
        self.peerAvatar = coolapkNormalizedURL(peerAvatar)
        self._viewModel = State(initialValue: ChatThreadViewModel(ukey: ukey, peerUID: peerUID))
    }

    private var visibleMessages: [ChatMessage] {
        viewModel.messages.filter { !($0.isLongTimeFlag && $0.message.isEmpty && $0.messagePic.isEmpty) }
    }

    private var resolvedPeerAvatar: String {
        if !peerAvatar.isEmpty { return peerAvatar }
        if let fromMsg = viewModel.messages.first(where: { $0.fromUID == peerUID && !$0.fromAvatar.isEmpty })?.fromAvatar {
            return fromMsg
        }
        return appState.cachedUserProfile(uid: peerUID)?.avatar ?? ""
    }

    public var body: some View {
        let items = visibleMessages
        let navAvatarID = "chat-nav-avatar-\(chatSeed)"

        VStack(spacing: 0) {
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
                            .padding(.top, index == 0 ? 4 : (showsTimeAbove ? 14 : (isFirstInCluster ? 10 : 4)))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(msg.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboardAndEmoji()
                    }
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isComposerFocused || showEmojiPanel || isHoldingSlotForKeyboard {
                            dismissKeyboardAndEmoji()
                        }
                    }
                )
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
                        if showEmojiPanel {
                            isHoldingSlotForKeyboard = true
                            showEmojiPanel = false
                        }
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
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 60_000_000)
                            withAnimation(.snappy(duration: 0.24)) {
                                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            composerBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { _, newMaxY in
            guard newMaxY > 100 else { return }
            containerGlobalMaxY = newMaxY
            if newMaxY > restingContainerMaxY {
                restingContainerMaxY = newMaxY
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            handleKeyboardFrameNotification(note, isHiding: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            handleKeyboardFrameNotification(note, isHiding: true)
        }
        .c001PageBackground()
        .navigationTitle(peerName.isEmpty ? "私信" : peerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.push(.user(
                        uid: peerUID,
                        initialUsername: peerName,
                        initialAvatar: resolvedPeerAvatar,
                        transitionID: navAvatarID
                    ))
                } label: {
                    AvatarView(url: resolvedPeerAvatar, size: 32)
                        .applyZoomSource(id: navAvatarID, in: zoomNamespace, cornerRadius: 16)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            appState.markThreadReadByUkey(ukey: ukey, uid: peerUID)
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
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: ChatMessage, isLastInCluster: Bool) -> some View {
        let activeUID = appState.accounts.activeUID ?? ""
        let isMine = !activeUID.isEmpty && msg.fromUID == activeUID
        let myAvatar = !msg.fromAvatar.isEmpty
            ? msg.fromAvatar
            : (appState.currentUserProfile?.avatar ?? appState.accounts.activeAccount?.avatar ?? "")
        let myName = appState.currentUserProfile?.username ?? appState.accounts.activeAccount?.displayName ?? ""
        let effectivePeerAvatar = !msg.fromAvatar.isEmpty ? msg.fromAvatar : resolvedPeerAvatar
        let picURL = msg.messagePic.isEmpty ? (viewModel.resolvedImages[msg.id]?.absoluteString ?? "") : msg.messagePic
        let hasText = !msg.message.isEmpty && msg.message != "[图片]"
        let bubbleShape = IMessageBubbleShape(isMine: isMine, showTail: isLastInCluster)
        let incomingFill: Color = colorScheme == .dark
            ? Color(.tertiarySystemGroupedBackground)
            : Color(uiColor: .systemGray5)
        let avatarSize: CGFloat = 40
        let rowAvatarID = "chat-row-avatar-\(chatSeed)-\(msg.id)"

        HStack(alignment: .bottom, spacing: 10) {
            if isMine {
                Spacer(minLength: 44)
            } else if isLastInCluster {
                Button {
                    appState.push(.user(
                        uid: peerUID,
                        initialUsername: peerName,
                        initialAvatar: effectivePeerAvatar,
                        transitionID: rowAvatarID
                    ))
                } label: {
                    AvatarView(url: effectivePeerAvatar, size: avatarSize)
                        .applyZoomSource(id: rowAvatarID, in: zoomNamespace, cornerRadius: avatarSize * 0.5)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: avatarSize, height: 1)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                if !picURL.isEmpty {
                    let chatPicPrefix = "chat-pic-\(chatSeed)-\(msg.id)"
                    Button {
                        appState.openMedia([FeedMedia(sourceUrl: picURL)], at: 0, sourcePrefix: chatPicPrefix)
                    } label: {
                        RemoteImageView(url: picURL, maxPixelSize: 720)
                            .frame(maxWidth: 256, maxHeight: 256)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .applyZoomSource(id: "\(chatPicPrefix)-0", in: zoomNamespace, cornerRadius: 20)
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
                        emojiPointSize: 22 * appState.settings.fontScale,
                        showEmoji: appState.settings.showEmoji
                    )
                    .font(.system(size: 16.5 * appState.settings.fontScale))
                    .lineSpacing(2.5)
                    .foregroundStyle(isMine ? Color.white : Color.primary)
                    .tint(isMine ? Color.white : Color.accentColor)
                    .padding(.vertical, 11)
                    .padding(.leading, isMine ? 16 : 20)
                    .padding(.trailing, isMine ? 20 : 16)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else if case let .failed(reason) = msg.deliveryState {
                    Text("发送失败：\(reason)")
                        .font(.caption)
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

            if isMine {
                if isLastInCluster {
                    Button {
                        if !activeUID.isEmpty {
                            appState.push(.user(
                                uid: activeUID,
                                initialUsername: myName,
                                initialAvatar: myAvatar,
                                transitionID: rowAvatarID
                            ))
                        }
                    } label: {
                        AvatarView(url: myAvatar, size: avatarSize)
                            .applyZoomSource(id: rowAvatarID, in: zoomNamespace, cornerRadius: avatarSize * 0.5)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: avatarSize, height: 1)
                }
            } else {
                Spacer(minLength: 44)
            }
        }
    }

    private func currentBottomSafeAreaInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow.safeAreaInsets.bottom
            }
        }
        return scenes.first?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    private func dismissKeyboardAndEmoji() {
        if isComposerFocused || keyboardEndMinY > 0 {
            isComposerFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        if showEmojiPanel || isHoldingSlotForKeyboard {
            withAnimation(.snappy(duration: 0.22)) {
                showEmojiPanel = false
                isHoldingSlotForKeyboard = false
            }
        }
    }

    private func handleKeyboardFrameNotification(_ note: Notification, isHiding: Bool) {
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let screenHeight = (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.height) ?? 852
        let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let refMaxY = restingContainerMaxY > 100
            ? restingContainerMaxY
            : (containerGlobalMaxY > 100 ? containerGlobalMaxY : (screenHeight - currentBottomSafeAreaInset()))
        let rawLiftFromResting = isHiding ? 0 : max(0, refMaxY - endFrame.minY)
        let isKeyboardVisible = !isHiding && endFrame.minY > 0 && endFrame.minY < screenHeight - 40 && rawLiftFromResting > 40

        if isKeyboardVisible && rawLiftFromResting > 160 {
            lastKnownKeyboardLift = rawLiftFromResting
        }

        if isKeyboardVisible {
            var transaction = Transaction(animation: .easeOut(duration: max(0.18, duration)))
            transaction.disablesAnimations = (showEmojiPanel || isHoldingSlotForKeyboard) && abs(rawLiftFromResting - lastKnownKeyboardLift) < 4
            withTransaction(transaction) {
                keyboardEndMinY = endFrame.minY
                isHoldingSlotForKeyboard = false
            }
        } else {
            if showEmojiPanel {
                keyboardEndMinY = 0
            } else {
                withAnimation(.easeOut(duration: max(0.18, duration))) {
                    keyboardEndMinY = 0
                    isHoldingSlotForKeyboard = false
                }
            }
        }
    }

    private func toggleEmojiAndKeyboard() {
        if showEmojiPanel {
            // Emoji -> Keyboard: hold the bottom slot at the exact current height while the keyboard rises
            isHoldingSlotForKeyboard = true
            showEmojiPanel = false
            isComposerFocused = true
        } else if isComposerFocused || currentKeyboardOverlap > 40 || currentSystemLift > 40 {
            // Keyboard -> Emoji: swap in place at the exact current keyboard height without moving the button bar
            let activeLift = max(currentKeyboardOverlap + currentSystemLift, lastKnownKeyboardLift)
            if activeLift > 160 {
                lastKnownKeyboardLift = activeLift
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showEmojiPanel = true
                keyboardEndMinY = 0
            }
            isComposerFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } else {
            // Both closed -> Open Emoji smoothly
            withAnimation(.snappy(duration: 0.24)) {
                showEmojiPanel = true
            }
        }
    }

    private var composerBar: some View {
        let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let slotHeight = activeBottomSlotHeight

        return VStack(spacing: 0) {
            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(.primary)
                    }

                    Button {
                        toggleEmojiAndKeyboard()
                    } label: {
                        Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling")
                            .font(.body.weight(.semibold))
                            .contentTransition(.identity)
                            .transaction { $0.animation = nil }
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(showEmojiPanel ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showEmojiPanel ? "切换键盘" : "选择表情")

                    TextField("发私信…", text: $draftText, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...5)
                        .focused($isComposerFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    Button {
                        let text = draftText
                        draftText = ""
                        Task { await viewModel.sendText(text, appState: appState) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
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
            .padding(.bottom, 8)

            if slotHeight > 0 {
                let kbOverlap = currentKeyboardOverlap
                let isEmojiKeyboardActive = showEmojiPanel && (kbOverlap > 40 || currentSystemLift > 40)
                let pickerHeight: CGFloat = isEmojiKeyboardActive ? 196 : max(252, slotHeight - 6)
                VStack(spacing: 0) {
                    if showEmojiPanel || isHoldingSlotForKeyboard {
                        EmojiPickerView(height: pickerHeight) { name in
                            draftText += name
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.5)
                        }
                        .padding(.bottom, 6)

                        if showEmojiPanel && kbOverlap > 40 {
                            Color.clear
                                .frame(height: kbOverlap)
                        }
                    } else {
                        Color.clear
                            .frame(height: slotHeight)
                    }
                }
                .frame(height: slotHeight, alignment: .top)
                .clipped()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
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
            return RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: rect)
        }

        if !showTail {
            let insetRect = CGRect(
                x: isMine ? 0 : tailWidth,
                y: 0,
                width: width - tailWidth,
                height: height
            )
            return RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: insetRect)
        }

        let bodyRight = width - tailWidth
        let radius = min(20, min(bodyRight, height) * 0.46)

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
