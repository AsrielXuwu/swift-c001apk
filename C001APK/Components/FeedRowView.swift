import AVKit
import CoolapkKit
import SwiftUI
import UIKit

public struct FeedRowView: View {
    public let feed: FeedItem
    public var originBadgeIsCloud: Bool? = nil
    public var showBothOriginBadges: Bool = false
    public var contextDeleteTitle: String? = nil
    public var onContextDelete: (() -> Void)? = nil
    public var onSelectFeed: (() -> Void)?
    public var onLikeChanged: ((Bool, Int) -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var isLiked: Bool
    @State private var likeCount: Int
    @State private var isLiking = false

    public init(
        feed: FeedItem,
        originBadgeIsCloud: Bool? = nil,
        showBothOriginBadges: Bool = false,
        contextDeleteTitle: String? = nil,
        onContextDelete: (() -> Void)? = nil,
        onSelectFeed: (() -> Void)? = nil,
        onLikeChanged: ((Bool, Int) -> Void)? = nil
    ) {
        self.feed = feed
        self.originBadgeIsCloud = originBadgeIsCloud
        self.showBothOriginBadges = showBothOriginBadges
        self.contextDeleteTitle = contextDeleteTitle
        self.onContextDelete = onContextDelete
        self.onSelectFeed = onSelectFeed
        self.onLikeChanged = onLikeChanged
        self._isLiked = State(initialValue: feed.isLiked)
        self._likeCount = State(initialValue: feed.likeNum)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader
            if feed.kind == .answer && !feed.questionID.isEmpty {
                questionBannerCard(questionID: feed.questionID, title: feed.questionTitle)
            }
            if !feed.subTabBadgeText.isEmpty {
                FeedSubTabBadgeView(feed: feed)
            }
            if let ratingInfo = feed.ratingInfo {
                FeedRatingCardView(info: ratingInfo, style: .card)
            }
            bodyContent
            if let videoInfo = feed.videoInfo {
                FeedVideoCardView(video: videoInfo)
            }
            if !feed.mediaItems.isEmpty {
                MediaGridView(items: feed.mediaItems)
            }
            if let source = feed.sourceFeed {
                forwardedQuoteCard(source)
            }
            if feed.hasPriceDisplay || !feed.resolvedExtraLinks.isEmpty {
                SecondHandOrExtraCard(feed: feed)
            }
            if !feed.relationEntities.isEmpty {
                FeedRelationEntitiesView(entities: feed.relationEntities, style: .card)
            }
            if let hotReply = feed.replyRows.first {
                hotReplyPreview(hotReply)
            }
            actionFooter
        }
        .padding(14)
        .c001CardStyle(cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
        .modifier(OptionalDestructiveContextMenu(title: contextDeleteTitle, action: onContextDelete))
        .applyZoomSource(id: "feed-\(transitionSeed)", in: zoomNamespace, cornerRadius: 22)
        .padding(.horizontal, 12)
        .onTapGesture {
            openFeedDetail()
        }
        .onChange(of: feed.isLiked) { _, newValue in
            isLiked = newValue
        }
        .onChange(of: feed.likeNum) { _, newValue in
            likeCount = newValue
        }
    }

    private func openFeedDetail() {
        if let onSelectFeed {
            onSelectFeed()
        } else {
            let targetID = feed.effectiveFeedID
            appState.push(.feed(
                id: targetID,
                initial: targetID == feed.id ? feed : nil,
                transitionID: "feed-\(transitionSeed)"
            ))
        }
    }

    // MARK: - Subviews

    private var authorHeader: some View {
        HStack(spacing: 10) {
            Button {
                if !feed.uid.isEmpty {
                    appState.push(.user(
                        uid: feed.uid,
                        initialUsername: feed.username,
                        initialAvatar: feed.avatar,
                        transitionID: "avatar-\(transitionSeed)"
                    ))
                }
            } label: {
                AvatarView(url: feed.avatar, size: 38)
                    .applyZoomSource(id: "avatar-\(transitionSeed)", in: zoomNamespace, cornerRadius: 19)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(feed.username.isEmpty ? "匿名酷友" : feed.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if feed.isHeadline {
                        Text("头条")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    if feed.isSelfOnly {
                        Label("仅自己可见", systemImage: "lock.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.orange)
                    }
                }

                let metaParts = [
                    Formatting.relativeTime(feed.dateline, fallback: feed.datelineText),
                    feed.isModified ? "已编辑" : "",
                    feed.readNum > 0 ? "\(Formatting.count(feed.readNum)) 浏览" : "",
                    feed.ipLocation,
                    feed.deviceTitle
                ].filter { !$0.isEmpty }
                if !metaParts.isEmpty {
                    Text(metaParts.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if showBothOriginBadges {
                HStack(spacing: 4) {
                    SourceOriginBadge(isCloud: false)
                    SourceOriginBadge(isCloud: true)
                }
            } else if let originBadgeIsCloud {
                SourceOriginBadge(isCloud: originBadgeIsCloud)
            }

            Menu {
                Button {
                    appState.favoritePickerFeed = feed
                } label: {
                    Label(
                        appState.historyAndFav.isLocallyFavorited(id: feed.id) ? "已收藏（管理收藏夹）" : "加入收藏夹…",
                        systemImage: appState.historyAndFav.isLocallyFavorited(id: feed.id) ? "star.fill" : "star"
                    )
                }

                Button {
                    appState.historyAndFav.toggleLocalFavorite(feed)
                    appState.showToast(appState.historyAndFav.isLocallyFavorited(id: feed.id) ? "已加入本机收藏" : "已取消本机收藏")
                } label: {
                    Label(
                        appState.historyAndFav.isLocallyFavorited(id: feed.id) ? "快速取消本机收藏" : "快速本机收藏",
                        systemImage: appState.historyAndFav.isLocallyFavorited(id: feed.id) ? "bookmark.fill" : "bookmark"
                    )
                }

                Button {
                    appState.copyLinkToPasteboard("https://www.coolapk.com/feed/\(feed.id)")
                } label: {
                    Label("复制链接", systemImage: "link")
                }

                Button {
                    UIPasteboard.general.string = FeedHTMLParser.plainText(feed.message)
                    appState.showToast("已复制正文")
                } label: {
                    Label("复制正文", systemImage: "doc.on.doc")
                }

                if !feed.uid.isEmpty {
                    Divider()
                    Button(role: .destructive) {
                        appState.blacklist.toggleUser(feed.uid)
                        appState.showToast(appState.blacklist.isUserBlocked(feed.uid) ? "已屏蔽该用户" : "已取消屏蔽")
                    } label: {
                        Label(
                            appState.blacklist.isUserBlocked(feed.uid) ? "移出黑名单" : "屏蔽该用户",
                            systemImage: "hand.raised"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        let baseFontSize = 15.5 * appState.settings.fontScale
        if !feed.messageTitle.isEmpty {
            Text(feed.messageTitle)
                .font(.system(size: 16.5 * appState.settings.fontScale, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }

        if !feed.message.isEmpty {
            RichTextView(
                html: feed.message,
                fontSize: baseFontSize,
                maxLines: 6,
                showEmoji: appState.settings.showEmoji,
                isSelectableText: false,
                onLinkTap: { link in
                    appState.openRawLink(link)
                },
                onCardTap: { openFeedDetail() }
            )
        }
    }

    private func questionBannerCard(questionID: String, title: String) -> some View {
        Button {
            appState.push(.feed(id: questionID))
        } label: {
            HStack(spacing: 8) {
                Text("原问题")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())

                Text(title.isEmpty ? "查看原问题" : title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .c001NestedSurface(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func forwardedQuoteCard(_ source: ForwardedContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !source.username.isEmpty {
                Text("@\(source.username)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !source.message.isEmpty {
                RichTextView(
                    html: source.message,
                    fontSize: 14 * appState.settings.fontScale,
                    textColor: .secondaryLabel,
                    maxLines: 4,
                    showEmoji: appState.settings.showEmoji,
                    isSelectableText: false,
                    onLinkTap: { link in
                        appState.openRawLink(link)
                    },
                    onCardTap: {
                        if !source.id.isEmpty {
                            appState.push(.feed(id: source.id, transitionID: "quote-\(transitionSeed)"))
                        }
                    }
                )
            }
            if !source.mediaItems.isEmpty {
                MediaGridView(items: source.mediaItems)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .c001NestedSurface(cornerRadius: 16)
        .applyZoomSource(id: "quote-\(transitionSeed)", in: zoomNamespace, cornerRadius: 16)
        .onTapGesture {
            if !source.id.isEmpty {
                appState.push(.feed(id: source.id, transitionID: "quote-\(transitionSeed)"))
            }
        }
    }

    // Subview helper kept above is replaced by shared FeedRelationEntitiesView below.

    private func hotReplyPreview(_ reply: ReplyItem) -> some View {
        (Text("\(reply.username)：")
            .font(.system(size: 13.5 * appState.settings.fontScale, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.82))
         + Text(FeedHTMLParser.plainText(reply.message))
            .font(.system(size: 13.5 * appState.settings.fontScale))
            .foregroundStyle(Color.secondary))
        .lineLimit(2)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .c001NestedSurface(cornerRadius: 14)
    }

    private var actionFooter: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    Task { await toggleLike() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        Text(likeCount > 0 ? Formatting.count(likeCount) : "赞")
                            .monospacedDigit()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isLiked ? Color.pink : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: isLiked)

                Button {
                    openFeedDetail()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                        Text(feed.replyNum > 0 ? Formatting.count(feed.replyNum) : "评论")
                            .monospacedDigit()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)

                Button {
                    if appState.accounts.isLoggedIn {
                        appState.composeMode = .forward(feed)
                    } else {
                        appState.showLoginSheet = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrowshape.turn.up.right")
                        Text(feed.forwardNum > 0 ? Formatting.count(feed.forwardNum) : "转发")
                            .monospacedDigit()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func toggleLike() async {
        guard appState.accounts.isLoggedIn else {
            appState.showLoginSheet = true
            return
        }
        guard !isLiking else { return }
        isLiking = true
        defer { isLiking = false }

        let targetLiked = !isLiked
        let prevLiked = isLiked
        let prevCount = likeCount
        isLiked = targetLiked
        likeCount = max(0, likeCount + (targetLiked ? 1 : -1))

        do {
            try await API.likeFeed(id: feed.id, liked: targetLiked)
            onLikeChanged?(isLiked, likeCount)
        } catch {
            isLiked = prevLiked
            likeCount = prevCount
            _ = await appState.handleAPIError(error)
        }
    }
}

struct OptionalDestructiveContextMenu: ViewModifier {
    let title: String?
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let title, let action {
            content.contextMenu {
                Button(title, role: .destructive, action: action)
            }
        } else {
            content
        }
    }
}

public struct SecondHandOrExtraCard: View {
    public let feed: FeedItem

    @Environment(AppState.self) private var appState

    public init(feed: FeedItem) {
        self.feed = feed
    }

    public var body: some View {
        let isDealCompleted = feed.dealStatusText.contains("完成")
            || feed.dealStatusText.contains("已售")
            || feed.dealStatusText.contains("已出")
            || feed.dealStatusText.contains("已交易")

        VStack(alignment: .leading, spacing: 8) {
            if feed.hasPriceDisplay {
                HStack(spacing: 8) {
                    Text(feed.isSecondHand ? "交易" : "价格")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((isDealCompleted ? Color.secondary : Color.orange).opacity(0.16), in: Capsule())
                        .foregroundStyle(isDealCompleted ? Color.secondary : Color.orange)

                    if !feed.dealStatusText.isEmpty {
                        Text(feed.dealStatusText)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((isDealCompleted ? Color.green : Color.secondary).opacity(0.16), in: Capsule())
                            .foregroundStyle(isDealCompleted ? Color.green : Color.secondary)
                            .lineLimit(1)
                    }

                    if !feed.priceText.isEmpty {
                        Text(feed.priceText)
                            .font(.headline.weight(.bold))
                            .strikethrough(isDealCompleted)
                            .foregroundStyle(isDealCompleted ? Color.secondary : Color.orange)
                    }

                    if !feed.originalPriceText.isEmpty {
                        Text(feed.originalPriceText)
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    if !feed.cityText.isEmpty {
                        Label(feed.cityText, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            let links = feed.resolvedExtraLinks
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(links) { link in
                        let isTrade = link.isTradeLink || feed.isSecondHand || FeedItem.isXianyuOrTradeURL(link.url)
                        Button {
                            openLink(link.url, preferSystemApp: isTrade)
                        } label: {
                            HStack(spacing: 10) {
                                if !link.pic.isEmpty {
                                    RemoteImageView(url: link.pic, maxPixelSize: 120)
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill((isTrade ? Color.yellow : Color.accentColor).opacity(0.18))
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            Image(systemName: isTrade ? "bag.fill" : "link")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(isTrade ? Color.orange : Color.accentColor)
                                        }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(link.title.isEmpty ? link.url : link.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(link.subtitle.isEmpty ? link.url : link.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Text("打开")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background((isTrade ? Color.orange : Color.accentColor).opacity(0.14), in: Capsule())
                                    .foregroundStyle(isTrade ? Color.orange : Color.accentColor)
                            }
                            .padding(10)
                            .c001NestedSurface(cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func openLink(_ raw: String, preferSystemApp: Bool) {
        if preferSystemApp, let url = URL(string: raw) {
            UIApplication.shared.open(url) { opened in
                if !opened {
                    Task { @MainActor in
                        appState.openRawLink(raw)
                    }
                }
            }
        } else {
            appState.openRawLink(raw)
        }
    }
}

private struct ConditionalNestedSurfaceModifier: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.c001NestedSurface(cornerRadius: cornerRadius)
        } else {
            content
        }
    }
}

public struct FeedRelationEntitiesView: View {
    public enum Style {
        case card
        case detail
    }

    public let entities: [FeedRelationEntity]
    public var style: Style = .card

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.oledPureBlack) private var oledPureBlack
    @State private var chipSeed = UUID().uuidString

    public init(entities: [FeedRelationEntity], style: Style = .card) {
        self.entities = entities
        self.style = style
    }

    public var body: some View {
        let iconSize: CGFloat = style == .detail ? 20 : 18
        let chipHeight: CGFloat = style == .detail ? 30 : 28
        WrappingChipsLayout(spacing: 6, lineSpacing: 6) {
            ForEach(entities) { entity in
                let chipTID = "relchip-\(chipSeed)-\(entity.id)"
                Button {
                    if !entity.url.isEmpty {
                        appState.openRawLink(entity.url, title: entity.title, transitionID: chipTID)
                    } else {
                        appState.push(.topic(tag: entity.title, transitionID: chipTID))
                    }
                } label: {
                    HStack(spacing: 5) {
                        if !entity.pic.isEmpty {
                            RemoteImageView(url: entity.pic, maxPixelSize: 64)
                                .frame(width: iconSize, height: iconSize)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        } else {
                            Image(systemName: iconName(for: entity))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: iconSize, height: iconSize)
                        }
                        Text(TopicItem.cleanTitle(entity.title))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: chipHeight)
                    .background(
                        colorScheme == .dark
                            ? Color(.tertiarySystemGroupedBackground)
                            : Color(.secondarySystemBackground),
                        in: Capsule()
                    )
                    .overlay {
                        if colorScheme == .dark {
                            Capsule()
                                .strokeBorder(Color.white.opacity(oledPureBlack ? 0.14 : 0.08), lineWidth: 0.6)
                        }
                    }
                    .applyZoomSource(id: chipTID, in: zoomNamespace, cornerRadius: chipHeight * 0.5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconName(for entity: FeedRelationEntity) -> String {
        let lowerType = entity.entityType.lowercased()
        let lowerURL = entity.url.lowercased()
        if lowerType == "product" || lowerURL.contains("/product/") { return "iphone" }
        if lowerType == "apk" || lowerURL.contains("/apk/") || lowerURL.contains("/game/") { return "app" }
        if lowerType == "dyh" || lowerURL.contains("/dyh/") { return "newspaper" }
        if lowerType == "collection" || lowerURL.contains("/collection/") { return "star" }
        return "number"
    }
}

public struct WrappingChipsLayout: Layout {
    public var spacing: CGFloat = 6
    public var lineSpacing: CGFloat = 6

    public init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                totalWidth = max(totalWidth, currentX - spacing)
                currentX = 0
                currentY += rowHeight + lineSpacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalWidth = max(totalWidth, max(0, currentX - spacing))
        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: currentY + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}


public struct FeedSubTabBadgeView: View {
    public let feed: FeedItem

    public init(feed: FeedItem) {
        self.feed = feed
    }

    private var iconName: String {
        switch feed.subTabID {
        case "1": return "battery.100.bolt"
        case "2": return "speedometer"
        case "5": return "exclamationmark.bubble.fill"
        default: return "sparkles"
        }
    }

    private var badgeColor: Color {
        switch feed.subTabID {
        case "1": return .green
        case "2": return .blue
        case "5": return .orange
        default: return .accentColor
        }
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
            Text(feed.subTabBadgeText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(badgeColor.opacity(0.14), in: Capsule())
        .foregroundStyle(badgeColor)
    }
}

public struct FeedRatingCardView: View {
    public enum Style {
        case card
        case detail
    }

    public let info: FeedRatingInfo
    public var style: Style = .card

    @Environment(AppState.self) private var appState

    public init(info: FeedRatingInfo, style: Style = .card) {
        self.info = info
        self.style = style
    }

    public var body: some View {
        let baseFontSize = (style == .detail ? 15.0 : 14.2) * appState.settings.fontScale
        let lineLimit: Int? = style == .detail ? nil : 3

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if !info.targetLogo.isEmpty {
                    RemoteImageView(url: info.targetLogo, maxPixelSize: 120)
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if !info.targetTitle.isEmpty {
                            Text(info.targetTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } else {
                            Text("酷友点评")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        if info.isOwner {
                            Text("机主")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if info.starCount > 0 || info.scoreOutOf10 > 0 {
                        HStack(spacing: 3) {
                            ForEach(1...5, id: \.self) { idx in
                                Image(systemName: idx <= info.starCount ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundStyle(idx <= info.starCount ? Color.orange : Color.secondary.opacity(0.35))
                            }
                            if info.scoreOutOf10 > 0 {
                                Text(String(format: "%.1f 分", info.scoreOutOf10))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.leading, 3)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                if !info.targetURL.isEmpty {
                    Button {
                        appState.openRawLink(info.targetURL, title: info.targetTitle)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !info.dimensions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(info.dimensions.prefix(style == .detail ? 8 : 4)) { dim in
                        HStack(spacing: 8) {
                            Text(dim.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .leading)
                                .lineLimit(1)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(Color.orange)
                                        .frame(width: max(4, geo.size.width * min(1.0, max(0, dim.score / 10.0))))
                                }
                            }
                            .frame(height: 6)

                            Text(String(format: "%.1f", dim.score))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }

            if !info.prosText.isEmpty {
                ratingSectionRow(label: "优点", color: .green, text: info.prosText, fontSize: baseFontSize, lineLimit: lineLimit)
            }
            if !info.consText.isEmpty {
                ratingSectionRow(label: "缺点", color: .red, text: info.consText, fontSize: baseFontSize, lineLimit: lineLimit)
            }
            if !info.summaryText.isEmpty {
                ratingSectionRow(label: "总评", color: .accentColor, text: info.summaryText, fontSize: baseFontSize, lineLimit: lineLimit)
            }
            if !info.additionText.isEmpty && style == .detail {
                ratingSectionRow(label: "追评", color: .purple, text: info.additionText, fontSize: baseFontSize, lineLimit: nil)
            }
        }
        .padding(12)
        .c001NestedSurface(cornerRadius: 16)
    }

    private func ratingSectionRow(label: String, color: Color, text: String, fontSize: CGFloat, lineLimit: Int?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundStyle(color)
                .padding(.top, 2)

            Text(FeedHTMLParser.plainText(text))
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

public struct FeedVideoCardView: View {
    public let video: FeedVideoInfo

    @Environment(AppState.self) private var appState
    @State private var showFullscreenPlayer = false

    public init(video: FeedVideoInfo) {
        self.video = video
    }

    public var body: some View {
        Button {
            if video.isExternalPage {
                appState.openRawLink(video.url, title: video.title)
            } else {
                showFullscreenPlayer = true
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    if !video.coverURL.isEmpty {
                        RemoteImageView(url: video.coverURL, maxPixelSize: 960, contentMode: .fill)
                            .aspectRatio(16.0 / 9.0, contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.black.opacity(0.82))
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                    }

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                }

                if !video.formattedDuration.isEmpty {
                    Text(video.formattedDuration)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.62), in: Capsule())
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFullscreenPlayer) {
            if let streamURL = URL(string: video.url) {
                NavigationStack {
                    VideoPlayer(player: AVPlayer(url: streamURL))
                        .ignoresSafeArea()
                        .navigationTitle(video.title.isEmpty ? "视频播放" : video.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("完成") {
                                    showFullscreenPlayer = false
                                }
                            }
                        }
                }
            }
        }
    }
}
