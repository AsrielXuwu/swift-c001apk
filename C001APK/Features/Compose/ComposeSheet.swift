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
                Color.black.opacity(0.24)
                    .ignoresSafeArea()
                    .onTapGesture {
                        resignComposeKeyboardImmediately()
                        withAnimation(.easeOut(duration: 0.20)) {
                            composeMode = nil
                        }
                    }
                    .transition(.opacity)

                ComposeSheet(mode: mode) {
                    resignComposeKeyboardImmediately()
                    withAnimation(.easeOut(duration: 0.20)) {
                        composeMode = nil
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.20), value: composeMode != nil)
    }
}

public struct ComposeSheet: View {
    public let mode: ComposeMode
    public var onDismiss: (() -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var envDismiss
    @State private var viewModel = ComposeViewModel()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showEmojiPanel = false
    @State private var activePanel: ActivePanel = .compose
    @State private var searchKeyword = ""
    @State private var searchedUsers: [UserBrief] = []
    @State private var searchedTopics: [TopicItem] = []
    @State private var isSearchingPicker = false
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

    private func closeSheet() {
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

    private var isQuickReply: Bool {
        if case .newFeed = mode { return false }
        return true
    }

    private var allowsImages: Bool {
        if case .forward = mode { return false }
        return true
    }

    public var body: some View {
        VStack(spacing: 12) {
            cardHeader

            switch activePanel {
            case .compose:
                composeBody
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            case .mentionUser:
                mentionUserPanel
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .mentionTopic:
                mentionTopicPanel
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.20), value: activePanel)
        .onAppear {
            if activePanel == .compose {
                isInputFocused = true
            }
        }
        .onChange(of: photoItems) { _, items in
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
    }

    private var cardHeader: some View {
        HStack {
            if activePanel == .compose {
                Button {
                    closeSheet()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
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
                        .frame(width: 34, height: 34)
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
                        .frame(width: 58, height: 34)
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
                        .frame(height: 34)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Color.clear.frame(width: 34, height: 34)
            }
        }
    }

    @ViewBuilder
    private var composeBody: some View {
        TextField(placeholderText, text: $viewModel.text, axis: .vertical)
            .font(.body)
            .lineLimit(isQuickReply ? 3...7 : 5...10)
            .focused($isInputFocused)
            .padding(12)
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
        }

        if showEmojiPanel {
            EmojiPickerView { name in
                viewModel.text += name
            }
            .frame(maxHeight: 175)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        toolbarStrip
    }

    private var mentionUserPanel: some View {
        VStack(spacing: 10) {
            pickerSearchBar(prompt: "搜索用户名") { value in
                isSearchingPicker = true
                let results = (try? await API.searchUsers(keyword: value)) ?? []
                searchedUsers = results
                isSearchingPicker = false
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if isSearchingPicker {
                        ProgressView()
                            .padding(.vertical, 24)
                    } else if searchedUsers.isEmpty {
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
                }
            }
            .frame(height: 220)
        }
    }

    private var mentionTopicPanel: some View {
        VStack(spacing: 10) {
            pickerSearchBar(prompt: "搜索话题标签") { value in
                isSearchingPicker = true
                let results = (try? await API.searchTags(keyword: value)) ?? []
                searchedTopics = results
                isSearchingPicker = false
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if isSearchingPicker {
                        ProgressView()
                            .padding(.vertical, 24)
                    } else if searchedTopics.isEmpty {
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
            .frame(height: 220)
        }
    }

    private func pickerSearchBar(prompt: String, onSearch: @escaping (String) async -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $searchKeyword)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isPickerSearchFocused)
                .onChange(of: searchKeyword) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        guard !trimmed.isEmpty else {
                            searchedUsers = []
                            searchedTopics = []
                            isSearchingPicker = false
                            return
                        }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                        await onSearch(trimmed)
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
        showEmojiPanel = false
        isInputFocused = false
        activePanel = panel
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            isPickerSearchFocused = true
        }
    }

    private func switchToCompose() {
        isPickerSearchFocused = false
        activePanel = .compose
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            isInputFocused = true
        }
    }

    private var toolbarStrip: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if allowsImages {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images) {
                        Image(systemName: "photo")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(.primary)
                    }
                }

                Button {
                    if !showEmojiPanel {
                        isInputFocused = false
                    } else {
                        isInputFocused = true
                    }
                    withAnimation(.snappy(duration: 0.22)) {
                        showEmojiPanel.toggle()
                    }
                } label: {
                    Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(showEmojiPanel ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)

                Button {
                    switchToPanel(.mentionUser)
                } label: {
                    Image(systemName: "at")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    switchToPanel(.mentionTopic)
                } label: {
                    Image(systemName: "number")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }
}
