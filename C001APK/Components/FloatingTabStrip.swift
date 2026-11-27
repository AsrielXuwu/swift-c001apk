import SwiftUI

/// Unified horizontal capsule segment strip matching HomeView typography, pill sizing, and Liquid Glass chrome.
public struct FloatingTabStrip<Item: Identifiable & Hashable>: View where Item.ID: Hashable {
    public let items: [Item]
    public let selection: Item?
    public let titleProvider: (Item) -> String
    public var badgeProvider: ((Item) -> Int)?
    public var onSelect: (Item) -> Void
    public var onReselect: ((Item) -> Void)?

    public init(
        items: [Item],
        selection: Item?,
        titleProvider: @escaping (Item) -> String,
        badgeProvider: ((Item) -> Int)? = nil,
        onSelect: @escaping (Item) -> Void,
        onReselect: ((Item) -> Void)? = nil
    ) {
        self.items = items
        self.selection = selection
        self.titleProvider = titleProvider
        self.badgeProvider = badgeProvider
        self.onSelect = onSelect
        self.onReselect = onReselect
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            let isSelected = (selection?.id == item.id)
                            let unreadCount = badgeProvider?(item) ?? 0
                            Button {
                                if isSelected {
                                    onReselect?(item)
                                } else {
                                    withAnimation(.snappy(duration: 0.24)) {
                                        onSelect(item)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(titleProvider(item))
                                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                        .lineLimit(1)
                                    if unreadCount > 0 {
                                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                                            .font(.caption2.weight(.bold))
                                            .monospacedDigit()
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.red, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
            .onChange(of: selection?.id) { _, newID in
                guard let newID else { return }
                withAnimation(.snappy(duration: 0.24)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }
}

/// Compact circular avatar + two-line metadata + capsule follow button for collapsed navigation toolbars.
/// Uses positive internal padding so all elements remain strictly inside the iOS 26 UINavigationBar capsule platter.
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
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                Button(action: onTapAvatar) {
                    HStack(spacing: 6) {
                        AvatarView(url: avatarURL, size: 24)

                        if !primaryLine.isEmpty || !secondaryLine.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                if !primaryLine.isEmpty {
                                    Text(primaryLine)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(uiColor: .label))
                                        .lineLimit(1)
                                }
                                if !secondaryLine.isEmpty {
                                    Text(secondaryLine)
                                        .font(.system(size: 9.5, weight: .regular))
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                        .lineLimit(1)
                                }
                            }
                            .frame(height: 24, alignment: .center)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .accessibilityLabel("回到顶部")

                if showFollowButton {
                    Button(action: onTapFollow) {
                        Text(isFollowed ? "已关注" : "关注")
                            .font(.system(size: 11.5, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .foregroundStyle(isFollowed ? Color(uiColor: .label) : Color.white)
                            .background(
                                isFollowed ? Color(uiColor: .tertiarySystemFill) : Color.accentColor,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        isFollowed
                                            ? Color(uiColor: .separator).opacity(0.45)
                                            : Color.white.opacity(0.28),
                                        lineWidth: 0.8
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .accessibilityLabel(isFollowed ? "取消关注" : "关注")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }
}

public struct PinnedEntityHeaderOverlay<Header: View, TabStrip: View>: View {
    public let scrollOffset: CGFloat
    public let hasHeader: Bool
    @Binding public var headerHeight: CGFloat
    @Binding public var stripHeight: CGFloat
    @ViewBuilder public let header: Header
    @ViewBuilder public let tabStrip: TabStrip

    public init(
        scrollOffset: CGFloat,
        hasHeader: Bool = true,
        headerHeight: Binding<CGFloat>,
        stripHeight: Binding<CGFloat>,
        @ViewBuilder header: () -> Header,
        @ViewBuilder tabStrip: () -> TabStrip
    ) {
        self.scrollOffset = scrollOffset
        self.hasHeader = hasHeader
        self._headerHeight = headerHeight
        self._stripHeight = stripHeight
        self.header = header()
        self.tabStrip = tabStrip()
    }

    private var effectiveHeaderHeight: CGFloat {
        hasHeader ? headerHeight : 0
    }

    private var maxCollapseDistance: CGFloat {
        max(0, effectiveHeaderHeight)
    }

    private var collapseOffset: CGFloat {
        if scrollOffset < 0 {
            return scrollOffset
        }
        return min(maxCollapseDistance, scrollOffset)
    }

    private var progress: CGFloat {
        guard maxCollapseDistance > 1 else { return 0 }
        return min(1, max(0, scrollOffset / maxCollapseDistance))
    }

    private var blurOpacity: Double {
        guard scrollOffset > 1, stripHeight > 1 else { return 0 }
        return Double(min(1, max(0, (scrollOffset - 1) / 22)))
    }

    public var body: some View {
        let visibleHeaderHeight = max(0, effectiveHeaderHeight - max(0, collapseOffset))
        let blurCoverHeight = visibleHeaderHeight + stripHeight + 120

        ZStack(alignment: .top) {
            if blurOpacity > 0.001 {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: blurCoverHeight)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black.opacity(0.90), location: 0.72),
                                .init(color: .black.opacity(0.42), location: 0.88),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(y: -120)
                    .opacity(blurOpacity)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                if hasHeader {
                    header
                        .onGeometryChange(for: CGFloat.self) { geo in
                            geo.size.height
                        } action: { _, h in
                            if h > 1, abs(h - headerHeight) > 0.5 {
                                headerHeight = h
                            }
                        }
                        .scaleEffect(1 - 0.04 * progress, anchor: .top)
                        .opacity(Double(max(0, 1 - progress * 1.25)))
                        .allowsHitTesting(progress < 0.75)
                }

                tabStrip
                    .onGeometryChange(for: CGFloat.self) { geo in
                        geo.size.height
                    } action: { _, h in
                        let clamped = max(0, h)
                        if abs(clamped - stripHeight) > 0.5 {
                            stripHeight = clamped
                        }
                    }
            }
            .offset(y: -collapseOffset)
        }
    }
}
