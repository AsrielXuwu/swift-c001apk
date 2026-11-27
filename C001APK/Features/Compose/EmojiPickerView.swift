import CoolapkKit
import SwiftUI

public struct EmojiPickerView: View {
    public var height: CGFloat
    public var onSelect: (String) -> Void

    @State private var selectedGroupIndex = 0
    @State private var searchText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    public init(height: CGFloat = 220, onSelect: @escaping (String) -> Void) {
        self.height = height
        self.onSelect = onSelect
    }

    private var groups: [CoolapkEmojiGroup] {
        CoolapkEmotionCatalog.groups
    }

    private var activeItems: [CoolapkEmojiItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            return CoolapkEmotionCatalog.allItems.filter { $0.name.localizedCaseInsensitiveContains(q) }
        }
        guard groups.indices.contains(selectedGroupIndex) else {
            return CoolapkEmotionCatalog.allItems
        }
        return groups[selectedGroupIndex].items
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(activeItems) { item in
                        Button {
                            onSelect(item.name)
                        } label: {
                            CoolapkEmojiAssetImage(item: item, size: 30)
                                .frame(width: 38, height: 38)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.label)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: max(160, height - 46))

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        let isSelected = selectedGroupIndex == index
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedGroupIndex = index
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let first = group.items.first {
                                    CoolapkEmojiAssetImage(item: first, size: 16)
                                }
                                Text(group.title)
                                    .font(.caption.weight(isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .frame(height: 45)
        }
        .frame(height: height)
        .background(.regularMaterial)
    }
}

public struct CoolapkEmojiAssetImage: View {
    public let item: CoolapkEmojiItem
    public var size: CGFloat = 22

    public init(item: CoolapkEmojiItem, size: CGFloat = 22) {
        self.item = item
        self.size = size
    }

    public var body: some View {
        if let url = CoolapkEmotionCatalog.url(forAssetPath: item.assetPath),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(item.label)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}
