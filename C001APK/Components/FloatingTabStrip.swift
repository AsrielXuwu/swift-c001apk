import SwiftUI

/// Unified horizontal capsule segment strip matching HomeView typography, pill sizing, and Liquid Glass chrome.
public struct FloatingTabStrip<Item: Identifiable & Hashable>: View where Item.ID: Hashable {
    public let items: [Item]
    public let selection: Item
    public let titleProvider: (Item) -> String
    public var onSelect: (Item) -> Void
    public var onReselect: ((Item) -> Void)?

    public init(
        items: [Item],
        selection: Item,
        titleProvider: @escaping (Item) -> String,
        onSelect: @escaping (Item) -> Void,
        onReselect: ((Item) -> Void)? = nil
    ) {
        self.items = items
        self.selection = selection
        self.titleProvider = titleProvider
        self.onSelect = onSelect
        self.onReselect = onReselect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(items) { item in
                            let isSelected = (item.id == selection.id)
                            Button {
                                if isSelected {
                                    onReselect?(item)
                                } else {
                                    withAnimation(.snappy(duration: 0.24)) {
                                        onSelect(item)
                                    }
                                }
                            } label: {
                                Text(titleProvider(item))
                                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                                        in: Capsule()
                                    )
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .onChange(of: selection.id) { _, newID in
                withAnimation(.snappy(duration: 0.24)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }
}

/// Compact circular avatar + two-line metadata + tight follow button for collapsed navigation toolbars.
public struct CollapsedNavEntityToolbar: ToolbarContent {
    public let avatarURL: String
    public let primaryLine: String
    public let secondaryLine: String
    public let isFollowed: Bool
    public let showFollowButton: Bool
    public let isDisabled: Bool
    public let onTapAvatar: () -> Void
    public let onTapFollow: () -> Void

    public init(
        avatarURL: String,
        primaryLine: String = "",
        secondaryLine: String = "",
        isFollowed: Bool,
        showFollowButton: Bool,
        isDisabled: Bool = false,
        onTapAvatar: @escaping () -> Void,
        onTapFollow: @escaping () -> Void
    ) {
        self.avatarURL = avatarURL
        self.primaryLine = primaryLine
        self.secondaryLine = secondaryLine
        self.isFollowed = isFollowed
        self.showFollowButton = showFollowButton
        self.isDisabled = isDisabled
        self.onTapAvatar = onTapAvatar
        self.onTapFollow = onTapFollow
    }

    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button(action: onTapAvatar) {
                HStack(spacing: 7) {
                    AvatarView(url: avatarURL, size: 28)

                    if !primaryLine.isEmpty || !secondaryLine.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            if !primaryLine.isEmpty {
                                Text(primaryLine)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            if !secondaryLine.isEmpty {
                                Text(secondaryLine)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: 112, alignment: .leading)
                    }
                }
            }
            .accessibilityLabel("回到顶部")

            if showFollowButton {
                Button(action: onTapFollow) {
                    Image(systemName: isFollowed ? "checkmark" : "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isFollowed ? Color.primary : Color.accentColor)
                }
                .disabled(isDisabled)
                .accessibilityLabel(isFollowed ? "取消关注" : "关注")
            }
        }
    }
}
