import CoolapkKit
import PhotosUI
import SwiftUI
import UIKit

@MainActor
private func resignComposeKeyboardImmediately() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

public struct ComposeFloatingOverlayHost: View {
    @Binding public var composeMode: ComposeMode?

    public init(composeMode: Binding<ComposeMode?>) {
        self._composeMode = composeMode
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let mode = composeMode {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        resignComposeKeyboardImmediately()
                        withAnimation(.easeOut(duration: 0.20)) {
                            composeMode = nil
                        }
                    }

                ComposeSheet(mode: mode) {
                    resignComposeKeyboardImmediately()
                    withAnimation(.easeOut(duration: 0.20)) {
                        composeMode = nil
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .scrollEdgeEffectHidden(true)
        .animation(.easeOut(duration: 0.20), value: composeMode != nil)
    }
}

public struct ComposeSheet: View {
    public let mode: ComposeMode
    public var onDismiss: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var envDismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = ComposeViewModel()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showEmojiPanel = false
    @State private var activePanel: ActivePanel = .compose
    @State private var searchKeyword = ""
    @State private var searchedUsers: [UserBrief] = []
    @State private var searchedTopics: [TopicItem] = []
    @State private var isSearchingPicker = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var lastKnownKeyboardHeight: CGFloat = 290
    @State private var isHoldingSlotForKeyboard = false
    @FocusState private var isInputFocused: Bool
    @FocusState private var isPickerSearchFocused: Bool

    private enum ActivePanel {
        case compose
        case mentionUser
        case mentionTopic
    }

    public init(mode: ComposeMode, onDismiss: (() -> Void)? = nil) {
        self.mode = mode
        self.onDismiss = onDismiss
    }

    private var activeBottomSlotHeight: CGFloat {
        if showEmojiPanel && keyboardHeight > 40 {
            return 210 + keyboardHeight
        }
        let emojiHeight = (showEmojiPanel || isHoldingSlotForKeyboard) ? max(260, lastKnownKeyboardHeight) : 0
        return max(keyboardHeight, emojiHeight)
    }

    private func closeSheet() {
        showEmojiPanel = false
        isHoldingSlotForKeyboard = false
        isInputFocused = false
        isPickerSearchFocused = false
        resignComposeKeyboardImmediately()
        if let onDismiss {
            onDismiss()
        } else {
            envDismiss()
        }
    }

    private var titleText: String {
        switch activePanel {
        case .mentionUser: return "提及用户"
        case .mentionTopic: return "插入话题"
        case .compose:
            switch mode {
            case .newFeed: return "发布动态"
            case .forward: return "转发动态"
            case let .replyToFeed(_, author): return "评论 @\(author)"
            case let .replyToComment(_, name): return "回复 @\(name)"
            }
        }
    }

    private var placeholderText: String {
        switch mode {
        case .newFeed: return "分享数码新鲜事、玩法或点评…"
        case .forward: return "写下转发感想（可选）…"
        case let .replyToFeed(_, author): return "写下给 @\(author) 的评论…"
        case let .replyToComment(_, name): return "回复 @\(name)…"
        }
    }

    private var pickerSearchPrompt: String {
        activePanel == .mentionTopic ? "搜索话题标签" : "搜索用户名"
    }

    private var isQuickReply: Bool {
        if case .newFeed = mode { return false }
        return true
    }

    private var allowsImages: Bool {
        if case .forward = mode { return false }
        return true
    }

    public var body: some View {
        let slotHeight = activeBottomSlotHeight
        composeRootContainer(slotHeight: slotHeight)
            .onAppear {
                if activePanel == .compose {
                    isInputFocused = true
                }
            }
            .onChange(of: isInputFocused) { _, focused in
                if focused, showEmojiPanel {
                    isHoldingSlotForKeyboard = true
                    showEmojiPanel = false
                }
            }
            .onChange(of: isPickerSearchFocused) { _, focused in
                if focused, showEmojiPanel {
                    isHoldingSlotForKeyboard = true
                    showEmojiPanel = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                handleKeyboardFrameNotification(note, isHiding: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
                handleKeyboardFrameNotification(note, isHiding: true)
            }
            .onChange(of: photoItems) { _, items in
                handleSelectedPhotoItems(items)
            }
    }

    @ViewBuilder
    private func composeRootContainer(slotHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            composeMainGlassCard
            if slotHeight > 0 {
                composeBottomEmojiSlot(slotHeight: slotHeight)
            }
        }
        .padding(.bottom, slotHeight > 0 ? 0 : 8)
    }

    private var composeMainGlassCard: some View {
        let isComposePanel = (activePanel == .compose)
        return VStack(spacing: 12) {
            cardHeader

            ZStack(alignment: .top) {
                composeBody
                    .opacity(isComposePanel ? 1 : 0)
                    .allowsHitTesting(isComposePanel)
                    .accessibilityHidden(!isComposePanel)

                pickerContainer
                    .opacity(isComposePanel ? 0 : 1)
                    .allowsHitTesting(!isComposePanel)
                    .accessibilityHidden(isComposePanel)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func composeBottomEmojiSlot(slotHeight: CGFloat) -> some View {
        let strokeColor = Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
        let pickerHeight: CGFloat = (showEmojiPanel && keyboardHeight > 40) ? 204 : max(252, slotHeight - 8)
        VStack(spacing: 0) {
            if showEmojiPanel || isHoldingSlotForKeyboard {
                EmojiPickerView(height: pickerHeight) { name in
                    viewModel.text += name
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 0.5)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                if showEmojiPanel && keyboardHeight > 40 {
                    Color.clear
                        .frame(height: keyboardHeight)
                }
            } else {
                Color.clear
                    .frame(height: slotHeight)
            }
        }
        .frame(height: slotHeight, alignment: .top)
        .clipped()
    }

    private func handleSelectedPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    viewModel.addImageData(data)
                }
            }
            photoItems.removeAll()
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

    private func handleKeyboardFrameNotification(_ note: Notification, isHiding: Bool) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        let screenHeight = keyWindow?.bounds.height ?? scenes.first?.screen.bounds.height ?? 852
        let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let bottomSafe = keyWindow?.safeAreaInsets.bottom ?? currentBottomSafeAreaInset()
        let isHidden = isHiding || endFrame.height <= 0 || endFrame.minY >= screenHeight - 20
        let rawOverlap = isHidden ? 0 : max(0, screenHeight - endFrame.minY - bottomSafe)
        let nextHeight = rawOverlap > 40 ? rawOverlap : 0

        if nextHeight > 180 {
            lastKnownKeyboardHeight = nextHeight
        }

        if nextHeight > 40 {
            if isHoldingSlotForKeyboard && abs(nextHeight - lastKnownKeyboardHeight) < 6 {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    keyboardHeight = nextHeight
                    isHoldingSlotForKeyboard = false
                }
            } else {
                withAnimation(.interpolatingSpring(stiffness: 340, damping: 34)) {
                    keyboardHeight = nextHeight
                    isHoldingSlotForKeyboard = false
                }
            }
        } else {
            withAnimation(.interpolatingSpring(stiffness: 340, damping: 34)) {
                keyboardHeight = 0
                if !showEmojiPanel {
                    isHoldingSlotForKeyboard = false
                }
            }
        }
    }

    private func toggleEmojiAndKeyboard() {
        if showEmojiPanel {
            isHoldingSlotForKeyboard = true
            showEmojiPanel = false
            if activePanel == .compose {
                isInputFocused = true
            } else {
                isPickerSearchFocused = true
            }
        } else if isInputFocused || isPickerSearchFocused || keyboardHeight > 40 {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showEmojiPanel = true
                keyboardHeight = 0
            }
            isInputFocused = false
            isPickerSearchFocused = false
            resignComposeKeyboardImmediately()
        } else {
            withAnimation(.snappy(duration: 0.24)) {
                showEmojiPanel = true
            }
        }
    }

    private var cardHeader: some View {
        HStack {
            if activePanel == .compose {
                Button {
                    closeSheet()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSubmitting)
            } else {
                Button {
                    switchToCompose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(titleText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            if activePanel == .compose {
                if viewModel.isSubmitting {
                    ProgressView()
                        .frame(width: 62, height: 38)
                } else {
                    Button {
                        Task {
                            if await viewModel.submit(mode: mode, appState: appState) {
                                closeSheet()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.caption.weight(.bold))
                            Text("发送")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Color.clear.frame(width: 38, height: 38)
            }
        }
    }

    private var composeBody: some View {
        VStack(spacing: 12) {
            TextField(placeholderText, text: $viewModel.text, axis: .vertical)
                .font(.body)
                .lineLimit(isQuickReply ? 4...7 : 5...10)
                .focused($isInputFocused)
                .padding(12)
                .frame(minHeight: isQuickReply ? 104 : 132, alignment: .topLeading)
                .background(
                    Color(.secondarySystemGroupedBackground).opacity(0.68),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )

            if !viewModel.pickedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.pickedImages) { item in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 68, height: 68)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                Button {
                                    viewModel.removeImage(id: item.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.65))
                                }
                                .padding(3)
                            }
                        }
                    }
                }
                .scrollEdgeEffectHidden(true)
            }

            if !isQuickReply && viewModel.subTabOption != .none {
                productSubTabInputRow
            }

            toolbarStrip
        }
    }

    @ViewBuilder
    private var productSubTabInputRow: some View {
        switch viewModel.subTabOption {
        case .none:
            EmptyView()
        case .daoshoujia:
            HStack(spacing: 8) {
                TextField("到手价（如 9599）", text: $viewModel.finalPriceInput)
                    .font(.subheadline)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground).opacity(0.68), in: Capsule())
                TextField("版本配置（如 16GB+512GB）", text: $viewModel.configNameInput)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground).opacity(0.68), in: Capsule())
            }
        case .battery:
            TextField("亮屏续航时长（小时，如 8.5）", text: $viewModel.batteryHoursInput)
                .font(.subheadline)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.68), in: Capsule())
        case .benchmark:
            TextField("安兔兔跑分成绩（如 2850000）", text: $viewModel.antutuScoreInput)
                .font(.subheadline)
                .keyboardType(.numberPad)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.68), in: Capsule())
        case .feedback:
            HStack(spacing: 6) {
                Text("严重程度：")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach([("1", "较低"), ("2", "一般"), ("3", "次要"), ("4", "严重"), ("5", "致命")], id: \.0) { code, label in
                    let isSel = viewModel.feedbackLevel == code
                    Button {
                        viewModel.feedbackLevel = code
                    } label: {
                        Text(label)
                            .font(.caption.weight(isSel ? .semibold : .regular))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(isSel ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(isSel ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var pickerContainer: some View {
        VStack(spacing: 10) {
            pickerSearchBar

            if activePanel != .compose {
                ScrollView {
                    LazyVStack(spacing: 8) {
                    if isSearchingPicker {
                        ProgressView()
                            .padding(.vertical, 24)
                    } else if activePanel == .mentionUser {
                        if searchedUsers.isEmpty {
                            Text(searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "输入用户名搜索" : "未找到匹配用户")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(searchedUsers) { user in
                                Button {
                                    viewModel.text += " @\(user.username) "
                                    switchToCompose()
                                } label: {
                                    HStack(spacing: 10) {
                                        AvatarView(url: user.avatar, size: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.username)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            if user.level > 0 {
                                                Text("Lv.\(user.level)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .c001CardStyle(cornerRadius: 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if activePanel == .mentionTopic {
                        if searchedTopics.isEmpty {
                            Text(searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "输入话题名称搜索" : "未找到相关话题")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(searchedTopics) { topic in
                                Button {
                                    viewModel.text += " #\(topic.title)# "
                                    switchToCompose()
                                } label: {
                                    HStack {
                                        Text("#\(topic.title)#")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(Formatting.count(topic.feedNum)) 动态")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .c001CardStyle(cornerRadius: 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        }
                    }
                }
                .scrollEdgeEffectHidden(true)
                .frame(height: isQuickReply ? 116 : 144)
            }
        }
    }

    private var pickerSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(pickerSearchPrompt, text: $searchKeyword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isPickerSearchFocused)
                .onChange(of: searchKeyword) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    let currentPanel = activePanel
                    Task {
                        guard !trimmed.isEmpty else {
                            searchedUsers = []
                            searchedTopics = []
                            isSearchingPicker = false
                            return
                        }
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        guard searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                        isSearchingPicker = true
                        if currentPanel == .mentionUser {
                            let results = (try? await API.searchUsers(keyword: trimmed)) ?? []
                            searchedUsers = results
                        } else if currentPanel == .mentionTopic {
                            let results = (try? await API.searchTags(keyword: trimmed)) ?? []
                            searchedTopics = results
                        }
                        isSearchingPicker = false
                    }
                }
            if !searchKeyword.isEmpty {
                Button {
                    searchKeyword = ""
                    searchedUsers = []
                    searchedTopics = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color(.secondarySystemGroupedBackground).opacity(0.68),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func switchToPanel(_ panel: ActivePanel) {
        searchKeyword = ""
        searchedUsers = []
        searchedTopics = []
        isSearchingPicker = false
        if showEmojiPanel {
            isHoldingSlotForKeyboard = true
            showEmojiPanel = false
        }
        withAnimation(.snappy(duration: 0.20)) {
            activePanel = panel
        }
        // Directly transfer focus to the already-mounted picker search TextField without resigning
        // first responder first, so the system keyboard stays open seamlessly without any bounce.
        isPickerSearchFocused = true
    }

    private func switchToCompose() {
        if showEmojiPanel {
            isHoldingSlotForKeyboard = true
            showEmojiPanel = false
        }
        withAnimation(.snappy(duration: 0.20)) {
            activePanel = .compose
        }
        // Directly transfer focus back to the already-mounted compose TextField without closing the keyboard.
        isInputFocused = true
    }

    private var toolbarStrip: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if allowsImages {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images) {
                        Image(systemName: "photo")
                            .font(.body.weight(.semibold))
                            .frame(width: 42, height: 42)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(.primary)
                    }
                }

                Button {
                    toggleEmojiAndKeyboard()
                } label: {
                    Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling")
                        .font(.body.weight(.semibold))
                        .contentTransition(.identity)
                        .transaction { $0.animation = nil }
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(showEmojiPanel ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)

                Button {
                    switchToPanel(.mentionUser)
                } label: {
                    Image(systemName: "at")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    switchToPanel(.mentionTopic)
                } label: {
                    Image(systemName: "number")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                if !isQuickReply {
                    Menu {
                        ForEach(ComposeViewModel.ProductSubTabOption.allCases) { opt in
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    viewModel.subTabOption = opt
                                }
                            } label: {
                                HStack {
                                    Text(opt.title)
                                    if viewModel.subTabOption == opt {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                                .font(.caption2.weight(.semibold))
                            Text(viewModel.subTabOption.title)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(viewModel.subTabOption == .none ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            viewModel.isSelfOnly.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isSelfOnly ? "lock.fill" : "globe")
                                .font(.caption2.weight(.semibold))
                            Text(viewModel.isSelfOnly ? "仅自己" : "公开")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(viewModel.isSelfOnly ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
