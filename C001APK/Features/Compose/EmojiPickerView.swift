import SwiftUI

public struct EmojiPickerView: View {
    public enum Category: String, CaseIterable, Identifiable {
        case recent = "最近"
        case coolapk = "酷安"
        case niuniu = "牛牛"
        case coin = "酷币"
        case unicode = "Emoji"

        public var id: String { rawValue }
    }

    private static let recentStorageKey = "c001apk.recent_emojis.v1"
    private static let maxRecentCount = 28
    private static let unicodeEmojis: [String] = [
        "😂", "🤣", "😭", "😍", "🥰", "😘", "😊", "😉",
        "🤔", "🤨", "😐", "😑", "😶", "🙄", "😏", "😣",
        "😥", "😮", "🤐", "😯", "😪", "😫", "🥱", "😴",
        "😌", "😛", "😜", "😝", "🤤", "😒", "😓", "😔",
        "😕", "🙃", "🫠", "🤑", "😲", "☹️", "🙁", "😖",
        "😞", "😟", "😤", "😢", "😦", "😧", "😨", "😩",
        "🤯", "😬", "😰", "😱", "🥵", "🥶", "😳", "🤪",
        "😵", "🥴", "😠", "😡", "🤬", "😷", "🤒", "🤕",
        "👍", "👎", "👏", "🙌", "🤝", "🙏", "💪", "🫡",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "💔", "🔥",
        "✨", "🎉", "🎊", "💯", "💢", "💥", "💫", "💦"
    ]

    public let height: CGFloat
    public let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: Category = .coolapk
    @State private var recentItems: [String] = Self.loadRecentItems()

    public init(height: CGFloat = 220, onSelect: @escaping (String) -> Void) {
        self.height = height
        self.onSelect = onSelect
    }

    private var availableCategories: [Category] {
        if recentItems.isEmpty {
            return [.coolapk, .niuniu, .coin, .unicode]
        }
        return Category.allCases
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedItems: [String] {
        let all = EmojiBundleStore.allNames
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
        }
        switch selectedCategory {
        case .recent:
            return recentItems.isEmpty ? all : recentItems
        case .coolapk:
            return all.filter { name in
                !name.hasPrefix("[牛牛") && !name.hasPrefix("[酷币") && !name.hasPrefix("[新酷币")
            }
        case .niuniu:
            return all.filter { $0.hasPrefix("[牛牛") }
        case .coin:
            return all.filter { $0.hasPrefix("[酷币") || $0.hasPrefix("[新酷币") }
        case .unicode:
            return Self.unicodeEmojis
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("筛选表情…", text: $searchText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if !isSearching {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableCategories) { category in
                            let isSelected = selectedCategory == category
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    selectedCategory = category
                                }
                            } label: {
                                Text(category.rawValue)
                                    .font(.caption.weight(isSelected ? .semibold : .medium))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(
                                        isSelected ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemFill),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollEdgeEffectHidden(true)
                .padding(.bottom, 4)
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 40), spacing: 8), count: 7), spacing: 10) {
                    ForEach(displayedItems, id: \.self) { item in
                        Button {
                            recordRecent(item)
                            onSelect(item)
                        } label: {
                            if let image = EmojiBundleStore.image(named: item) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .padding(4)
                            } else {
                                Text(item)
                                    .font(.system(size: 24))
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollEdgeEffectHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: height, alignment: .top)
        .clipped()
        .background(Color(.secondarySystemBackground))
        .onAppear {
            recentItems = Self.loadRecentItems()
        }
    }

    private func recordRecent(_ item: String) {
        var next = recentItems.filter { $0 != item }
        next.insert(item, at: 0)
        if next.count > Self.maxRecentCount {
            next = Array(next.prefix(Self.maxRecentCount))
        }
        recentItems = next
        UserDefaults.standard.set(next, forKey: Self.recentStorageKey)
    }

    private static func loadRecentItems() -> [String] {
        (UserDefaults.standard.stringArray(forKey: recentStorageKey) ?? [])
            .filter { !$0.isEmpty }
    }
}
