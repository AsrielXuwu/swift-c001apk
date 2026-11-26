import CoolapkKit
import PhotosUI
import SwiftUI

public struct ComposeSheet: View {
    public let mode: ComposeMode

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ComposeViewModel()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showEmojiPanel = false
    @State private var showMentionUserSheet = false
    @State private var showMentionTopicSheet = false
    @FocusState private var isInputFocused: Bool

    public init(mode: ComposeMode) {
        self.mode = mode
    }

    private var titleText: String {
        switch mode {
        case .newFeed: return "发布动态"
        case .forward: return "转发动态"
        case let .replyToFeed(_, author): return "评论 @\(author)"
        case let .replyToComment(_, name): return "回复 @\(name)"
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
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSubmitting)

                    Spacer()

                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer()

                    if viewModel.isSubmitting {
                        ProgressView()
                            .frame(width: 58, height: 34)
                    } else {
                        Button {
                            Task {
                                if await viewModel.submit(mode: mode, appState: appState) {
                                    dismiss()
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
                }

                TextField(placeholderText, text: $viewModel.text, axis: .vertical)
                    .font(.body)
                    .lineLimit(isQuickReply ? 3...7 : 5...10)
                    .focused($isInputFocused)
                    .padding(12)
                    .background(
                        Color(.secondarySystemGroupedBackground).opacity(0.72),
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
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                toolbarStrip
            }
            .padding(14)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .task {
            isInputFocused = true
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
        .sheet(isPresented: $showMentionUserSheet) {
            MentionUserPickerSheet { username in
                viewModel.text += " @\(username) "
            }
        }
        .sheet(isPresented: $showMentionTopicSheet) {
            MentionTopicPickerSheet { topic in
                viewModel.text += " #\(topic)# "
            }
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
                    showMentionUserSheet = true
                } label: {
                    Image(systemName: "at")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    showMentionTopicSheet = true
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

struct MentionUserPickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var users: [UserBrief] = []

    var body: some View {
        NavigationStack {
            List(users) { user in
                Button {
                    onSelect(user.username)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(url: user.avatar, size: 32)
                        Text(user.username)
                    }
                }
            }
            .navigationTitle("提及用户")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $keyword, prompt: "搜索用户名")
            .onChange(of: keyword) { _, value in
                Task {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { users = []; return }
                    users = (try? await API.searchUsers(keyword: trimmed)) ?? []
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct MentionTopicPickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var topics: [TopicItem] = []

    var body: some View {
        NavigationStack {
            List(topics) { topic in
                Button {
                    onSelect(topic.title)
                    dismiss()
                } label: {
                    Text("#\(topic.title)#")
                }
            }
            .navigationTitle("插入话题")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $keyword, prompt: "搜索话题")
            .onChange(of: keyword) { _, value in
                Task {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { topics = []; return }
                    topics = (try? await API.searchTags(keyword: trimmed)) ?? []
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
