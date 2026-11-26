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
            if !feed.targetTitle.isEmpty {
                targetEntityStrip
            }
            if let hotReply = feed.replyRows.first {
                hotReplyPreview(hotReply)
            }
            actionFooter
        }
        .padding(14)
        .c001CardStyle(cornerRadius: 16)
        .padding(.horizontal, 12)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if let onSelectFeed {
                onSelectFeed()
            } else {
                appState.push(.feed(id: feed.id, initial: feed))
            }
        }
        .onChange(of: feed.isLiked) { _, newValue in
            isLiked = newValue
        }
        .onChange(of: feed.likeNum) { _, newValue in
            likeCount = newValue
        }
    }

    // MARK: - Subviews

    private var authorHeader: some View {
        HStack(spacing: 10) {
            Button {
                if !feed.uid.isEmpty {
                    appState.push(.user(uid: feed.uid, transitionID: "avatar-\(transitionSeed)"))
                }
            } label: {
                AvatarView(url: feed.avatar, size: 36)
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
                    appState.historyAndFav.toggleLocalFavorite(feed)
                    appState.showToast(appState.historyAndFav.isLocallyFavorited(id: feed.id) ? "已加入本地收藏" : "已取消本地收藏")
                } label: {
                    Label(
                        appState.historyAndFav.isLocallyFavorited(id: feed.id) ? "取消本地收藏" : "本地收藏",
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
                showEmoji: appState.settings.showEmoji
            ) { link in
                appState.openRawLink(link)
            }
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
                    showEmoji: appState.settings.showEmoji
                ) { link in
                    appState.openRawLink(link)
                }
            }
            if !source.mediaItems.isEmpty {
                MediaGridView(items: source.mediaItems)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .applyZoomSource(id: "quote-\(transitionSeed)", in: zoomNamespace)
        .onTapGesture {
            if !source.id.isEmpty {
                appState.push(.feed(id: source.id, transitionID: "quote-\(transitionSeed)"))
            }
        }
    }

    private var targetEntityStrip: some View {
        Button {
            if !feed.targetURL.isEmpty {
                appState.openRawLink(feed.targetURL)
            } else {
                appState.push(.topic(tag: feed.targetTitle))
            }
        } label: {
            HStack(spacing: 8) {
                if !feed.targetPic.isEmpty {
                    RemoteImageView(url: feed.targetPic, maxPixelSize: 80)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "number")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(feed.targetTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

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
                    if let onSelectFeed {
                        onSelectFeed()
                    } else {
                        appState.push(.feed(id: feed.id, initial: feed))
                    }
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
