import CoolapkKit
import SwiftUI
import UIKit

public struct FeedRowView: View {
    public let feed: FeedItem
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
        onSelectFeed: (() -> Void)? = nil,
        onLikeChanged: ((Bool, Int) -> Void)? = nil
    ) {
        self.feed = feed
        self.onSelectFeed = onSelectFeed
        self.onLikeChanged = onLikeChanged
        self._isLiked = State(initialValue: feed.isLiked)
        self._likeCount = State(initialValue: feed.likeNum)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            authorHeader
            bodyContent
            if !feed.mediaItems.isEmpty {
                MediaGridView(items: feed.mediaItems)
            }
            if let source = feed.sourceFeed {
                forwardedQuoteCard(source)
            }
            if feed.isSecondHand || !feed.extraURL.isEmpty {
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
        .padding(.horizontal, 12)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .applyZoomSource(id: "feed-\(transitionSeed)", in: zoomNamespace, cornerRadius: 22)
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
                    .applyZoomSource(id: "avatar-\(transitionSeed)", in: zoomNamespace)
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
                }

                let metaParts = [
                    Formatting.relativeTime(feed.dateline, fallback: feed.datelineText),
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
                    UIPasteboard.general.string = "https://www.coolapk.com/feed/\(feed.id)"
                    appState.showToast("已复制链接")
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
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .applyZoomSource(id: "quote-\(transitionSeed)", in: zoomNamespace)
        .onTapGesture {
            if !source.id.isEmpty {
                appState.push(.feed(id: source.id, transitionID: "quote-\(transitionSeed)"))
            }
        }
    }

    // Subview helper kept above is replaced by shared FeedRelationEntitiesView below.

    private func hotReplyPreview(_ reply: ReplyItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(reply.username)：")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(FeedHTMLParser.plainText(reply.message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    .frame(maxWidth: .infinity, minHeight: 32)
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
                    .frame(maxWidth: .infinity, minHeight: 32)
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
                    .frame(maxWidth: .infinity, minHeight: 32)
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

public struct SecondHandOrExtraCard: View {
    public let feed: FeedItem

    @Environment(AppState.self) private var appState

    public init(feed: FeedItem) {
        self.feed = feed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if feed.isSecondHand {
                HStack(spacing: 8) {
                    Text("二手交易")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.orange)

                    if !feed.priceText.isEmpty {
                        Text(feed.priceText)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.orange)
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
                    } else if !feed.dealStatusText.isEmpty {
                        Text(feed.dealStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            let actionURL = !feed.xianyuURL.isEmpty ? feed.xianyuURL : feed.extraURL
            if !actionURL.isEmpty {
                let isSpecificXianyu = FeedItem.isSpecificXianyuURL(actionURL)
                let isTrade = FeedItem.isXianyuOrTradeURL(actionURL)
                Button {
                    openLink(actionURL, preferSystemApp: isTrade)
                } label: {
                    HStack(spacing: 10) {
                        if !feed.extraPic.isEmpty {
                            RemoteImageView(url: feed.extraPic, maxPixelSize: 120)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill((isTrade ? Color.yellow : Color.accentColor).opacity(0.18))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: isTrade ? "bag.fill" : "link")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(isTrade ? Color.orange : Color.accentColor)
                                }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                !feed.extraTitle.isEmpty
                                    ? feed.extraTitle
                                    : (isSpecificXianyu ? "前往闲鱼查看宝贝详情" : (isTrade ? "前往平台查看详情" : actionURL))
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                            Text(isSpecificXianyu ? "点击跳转闲鱼 · \(actionURL)" : (isTrade ? "点击跳转平台 · \(actionURL)" : actionURL))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Text(isTrade ? "跳转平台" : "打开")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background((isTrade ? Color.orange : Color.accentColor).opacity(0.14), in: Capsule())
                            .foregroundStyle(isTrade ? Color.orange : Color.accentColor)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(feed.isSecondHand && feed.xianyuURL.isEmpty && feed.extraURL.isEmpty ? 10 : 0)
        .background(
            (feed.isSecondHand && feed.xianyuURL.isEmpty && feed.extraURL.isEmpty)
                ? Color(.secondarySystemBackground)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
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

public struct FeedRelationEntitiesView: View {
    public enum Style {
        case card
        case detail
    }

    public let entities: [FeedRelationEntity]
    public var style: Style = .card

    @Environment(AppState.self) private var appState

    public init(entities: [FeedRelationEntity], style: Style = .card) {
        self.entities = entities
        self.style = style
    }

    public var body: some View {
        let iconSize: CGFloat = style == .detail ? 20 : 18
        let chipHeight: CGFloat = style == .detail ? 30 : 28
        WrappingChipsLayout(spacing: 6, lineSpacing: 6) {
            ForEach(entities) { entity in
                Button {
                    if !entity.url.isEmpty {
                        appState.openRawLink(entity.url, title: entity.title)
                    } else {
                        appState.push(.topic(tag: entity.title))
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
                        Color(style == .detail ? .tertiarySystemGroupedBackground : .secondarySystemBackground),
                        in: Capsule()
                    )
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
