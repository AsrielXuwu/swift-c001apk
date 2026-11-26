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

    private var allowsImages: Bool {
        if case .forward = mode { return false }
        return true
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $viewModel.text)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .frame(minHeight: 160)

                if !viewModel.pickedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.pickedImages) { item in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    Button {
                                        viewModel.removeImage(id: item.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .padding(4)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }

                Spacer(minLength: 0)

                if showEmojiPanel {
                    EmojiPickerView { name in
                        viewModel.text += name
                    }
                }

                toolbarStrip
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(viewModel.isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Button("发送") {
                            Task {
                                if await viewModel.submit(mode: mode, appState: appState) {
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                    }
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
                    showEmojiPanel.toggle()
                } label: {
                    Image(systemName: showEmojiPanel ? "keyboard" : "face.smiling")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    showMentionUserSheet = true
                } label: {
                    Image(systemName: "at")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    showMentionTopicSheet = true
                } label: {
                    Image(systemName: "number")
                        .font(.body.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
