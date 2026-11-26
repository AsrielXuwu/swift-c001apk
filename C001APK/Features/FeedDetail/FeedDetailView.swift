import CoolapkKit
import SwiftUI
import UIKit

public struct FeedDetailView: View {
    public let feedID: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var viewModel: FeedDetailViewModel
    @State private var detailSeed = UUID().uuidString
    @State private var selectedReplyForThread: ReplyItem?
    @State private var engagementMode: EngagementSelection?
    @State private var isExporting = false
    @State private var pendingExport: PreparedExportResult?
    @State private var showExportWarningAlert = false
    @State private var shareURL: URL?

    private enum EngagementSelection: Identifiable {
        case likes(String)
        case forwards(String)
        case history(String)

        var id: String {
            switch self {
            case let .likes(id): return "likes-\(id)"
            case let .forwards(id): return "forwards-\(id)"
            case let .history(id): return "history-\(id)"
            }
        }

        var mode: EngagementListView.Mode {
            switch self {
            case let .likes(id): return .likes(feedID: id)
            case let .forwards(id): return .forwards(feedID: id)
            case let .history(id): return .history(feedID: id)
            }
        }
    }

    public init(feedID: String, initialFeed: FeedItem? = nil) {
        self.feedID = feedID
        self._viewModel = State(initialValue: FeedDetailViewModel(feedID: feedID, initialFeed: initialFeed))
    }

    public var body: some View {
        Group {
            if let feed = viewModel.feed {
                if let match = appState.contentFilter.match(feed: feed), !viewModel.temporarilyRevealedFilter {
                    ContentFilterGateView(
                        reason: match.reason,
                        onRevealTemporarily: {
                            viewModel.temporarilyRevealedFilter = true
                        },
                        onAllowAuthor: feed.uid.isEmpty ? nil : {
                            appState.contentFilter.allowAuthor(feed.uid)
                            appState.showToast("已始终允许该作者")
                        }
                    )
                } else {
                    detailScroll(feed)
                }
            } else if viewModel.isLoadingFeed {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(viewModel.errorMessage ?? "无法读取动态内容")
                } actions: {
                    Button("重试") { Task { await viewModel.loadAll(appState: appState) } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(viewModel.feed?.feedTypeName ?? "动态详情")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if let feed = viewModel.feed {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Menu {
                            Button {
                                Task { await startExport(feed: feed, format: .markdown) }
                            } label: {
                                Label("保存为 Markdown", systemImage: "doc.text")
                            }
                            Button {
                                Task { await startExport(feed: feed, format: .html) }
                            } label: {
                                Label("保存为离线 HTML", systemImage: "safari")
                            }
                            Divider()
                            Button {
                                UIPasteboard.general.string = "https://www.coolapk.com/feed/\(feed.id)"
                                appState.showToast("已复制动态链接")
                            } label: {
                                Label("复制链接", systemImage: "link")
                            }
                            Button {
                                engagementMode = .likes(feed.id)
                            } label: {
                                Label("点赞的人", systemImage: "hand.thumbsup")
                            }
                            Button {
                                engagementMode = .forwards(feed.id)
                            } label: {
                                Label("转发列表", systemImage: "arrowshape.turn.up.right")
                            }
                            if feed.changeCount > 0 {
                                Button {
                                    engagementMode = .history(feed.id)
                                } label: {
                                    Label("编辑记录", systemImage: "clock.arrow.circlepath")
                                }
                            }
                            if feed.uid == appState.accounts.activeUID {
                                Divider()
                                Button(role: .destructive) {
                                    Task {
                                        if await viewModel.deleteFeed(appState: appState) {
                                            dismiss()
                                        }
                                    }
                                } label: {
                                    Label("删除动态", systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let feed = viewModel.feed {
                bottomInteractionBar(feed)
            }
        }
        .sheet(item: $selectedReplyForThread) { reply in
            ReplyThreadSheet(rootReply: reply, feedAuthorUID: viewModel.feed?.uid ?? "")
        }
        .sheet(item: $engagementMode) { selection in
            NavigationStack {
                EngagementListView(mode: selection.mode)
            }
        }
        .sheet(item: Binding(
            get: { shareURL.map { ExportShareItem(url: $0) } },
            set: { if $0 == nil { shareURL = nil } }
        )) { item in
            ActivityShareSheet(items: [item.url])
        }
        .alert("部分内容提示", isPresented: $showExportWarningAlert) {
            Button("仍然保存") {
                if let result = pendingExport {
                    shareURL = result.fileURL
                }
                pendingExport = nil
            }
            Button("取消", role: .cancel) {
                pendingExport = nil
            }
        } message: {
            Text((pendingExport?.warnings ?? []).joined(separator: "\n"))
        }
        .task(id: feedID) {
            await viewModel.loadAll(appState: appState)
        }
        .onChange(of: appState.feedRefreshTrigger) { _, _ in
            Task { await viewModel.loadAll(appState: appState) }
        }
    }

    private func detailScroll(_ feed: FeedItem) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    authorBar(feed)

                    if !feed.messageTitle.isEmpty {
                        Text(feed.messageTitle)
                            .font(.system(size: 20 * appState.settings.fontScale, weight: .bold))
                    }

                    if !feed.articleParts.isEmpty {
                        articleContent(feed)
                    } else {
                        if !feed.message.isEmpty {
                            RichTextView(
                                html: feed.message,
                                fontSize: 16 * appState.settings.fontScale,
                                showEmoji: appState.settings.showEmoji
                            ) { link in
                                appState.openRawLink(link)
                            }
                        }
                        if !feed.mediaItems.isEmpty {
                            MediaGridView(items: feed.mediaItems)
                        }
                    }

                    if let vote = feed.vote {
                        voteSection(vote)
                    }

                    if let source = feed.sourceFeed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("转发自 @\(source.username)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if !source.message.isEmpty {
                                RichTextView(
                                    html: source.message,
                                    fontSize: 14.5 * appState.settings.fontScale,
                                    textColor: .secondaryLabel,
                                    showEmoji: appState.settings.showEmoji
                                ) { link in
                                    appState.openRawLink(link)
                                }
                            }
                            if !source.mediaItems.isEmpty {
                                MediaGridView(items: source.mediaItems)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .applyZoomSource(id: "detail-quote-\(detailSeed)", in: zoomNamespace)
                        .onTapGesture {
                            if !source.id.isEmpty {
                                appState.push(.feed(id: source.id, transitionID: "detail-quote-\(detailSeed)"))
                            }
                        }
                    }

                    if !feed.targetTitle.isEmpty {
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
                                        .frame(width: 24, height: 24)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                } else {
                                    Image(systemName: "number")
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text(feed.targetTitle)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    metadataSummary(feed)
                }
                .padding(16)
                .c001CardStyle(cornerRadius: 22)
                .padding(.horizontal, 12)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)

                if feed.kind == .question, !viewModel.answers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("精选回答")
                            .font(.headline)
                            .padding(.horizontal, 16)
                        ForEach(viewModel.answers) { row in
                            HomeRowRenderer(row: row)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }

                repliesHeader(feed)

                repliesSection(feed)
            }
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
        .refreshable {
            await viewModel.loadAll(appState: appState)
        }
    }

    private func authorBar(_ feed: FeedItem) -> some View {
        HStack(spacing: 10) {
            Button {
                if !feed.uid.isEmpty {
                    appState.push(.user(uid: feed.uid, transitionID: "detail-author-\(detailSeed)"))
                }
            } label: {
                AvatarView(url: feed.avatar, size: 42)
                    .applyZoomSource(id: "detail-author-\(detailSeed)", in: zoomNamespace)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.username.isEmpty ? "匿名酷友" : feed.username)
                    .font(.headline)
                let meta = [Formatting.relativeTime(feed.dateline, fallback: feed.datelineText), feed.ipLocation, feed.deviceTitle]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func articleContent(_ feed: FeedItem) -> some View {
        if !feed.cover.isEmpty {
            let coverPrefix = "cover-\(detailSeed)"
            Button {
                appState.openMedia([FeedMedia(sourceUrl: feed.cover, contentId: feed.id, contentType: .article)], at: 0, sourcePrefix: coverPrefix)
            } label: {
                RemoteImageView(url: feed.cover, maxPixelSize: 1400)
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .applyZoomSource(id: "\(coverPrefix)-0", in: zoomNamespace)
            }
            .buttonStyle(.plain)
        }

        ForEach(feed.articleParts) { part in
            switch part.type {
            case "title":
                if !part.title.isEmpty {
                    Text(FeedHTMLParser.plainText(part.title))
                        .font(.system(size: 18 * appState.settings.fontScale, weight: .semibold))
                        .padding(.top, 4)
                }
            case "text":
                if !part.message.isEmpty {
                    RichTextView(
                        html: part.message,
                        fontSize: 16 * appState.settings.fontScale,
                        showEmoji: appState.settings.showEmoji
                    ) { link in
                        appState.openRawLink(link)
                    }
                }
            case "image":
                if !part.url.isEmpty {
                    let partPrefix = "art-\(detailSeed)-\(part.id)"
                    VStack(spacing: 4) {
                        Button {
                            appState.openMedia([FeedMedia(sourceUrl: part.url, contentId: feed.id, contentType: .article)], at: 0, sourcePrefix: partPrefix)
                        } label: {
                            RemoteImageView(url: part.url, maxPixelSize: 1400, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .applyZoomSource(id: "\(partPrefix)-0", in: zoomNamespace)
                        }
                        .buttonStyle(.plain)
                        if !part.description.isEmpty {
                            Text(part.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case "shareUrl":
                if !part.url.isEmpty {
                    Button {
                        appState.openRawLink(part.url)
                    } label: {
                        Label(part.title.isEmpty ? part.url : part.title, systemImage: "link")
                            .font(.subheadline)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            default:
                EmptyView()
            }
        }
    }

    private func voteSection(_ vote: VoteInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vote.title.isEmpty ? "投票" : vote.title)
                .font(.subheadline.weight(.semibold))
            ForEach(vote.options) { opt in
                let ratio = vote.totalVotes > 0 ? Double(opt.count) / Double(vote.totalVotes) : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(opt.title).font(.subheadline)
                        Spacer()
                        Text("\(opt.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: ratio)
                }
            }
            Text("共 \(vote.totalVotes) 人参与 \(vote.endTimeText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metadataSummary(_ feed: FeedItem) -> some View {
        HStack(spacing: 16) {
            Button {
                engagementMode = .likes(feed.id)
            } label: {
                Text("\(Formatting.count(feed.likeNum)) 赞")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text("\(Formatting.count(feed.replyNum)) 评论")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                engagementMode = .forwards(feed.id)
            } label: {
                Text("\(Formatting.count(feed.forwardNum)) 转发")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func repliesHeader(_ feed: FeedItem) -> some View {
        HStack(spacing: 8) {
            Text("全部评论")
                .font(.headline)
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        viewModel.authorOnly.toggle()
                        Task { await viewModel.reloadReplies(appState: appState) }
                    } label: {
                        Text("只看楼主")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.authorOnly ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .foregroundStyle(viewModel.authorOnly ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(FeedDetailViewModel.ReplySortMode.allCases) { mode in
                            Button {
                                viewModel.sortMode = mode
                                Task { await viewModel.reloadReplies(appState: appState) }
                            } label: {
                                HStack {
                                    Text(mode.label)
                                    if viewModel.sortMode == mode { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        Label(viewModel.sortMode.label, systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func repliesSection(_ feed: FeedItem) -> some View {
        let visibleReplies = viewModel.replies.filter { reply in
            !appState.blacklist.isUserBlocked(reply.uid) && appState.contentFilter.match(reply: reply) == nil
        }

        let coinOnlyReplies = appState.settings.foldCoinReplies
            ? visibleReplies.filter { !$0.isTop && FeedHTMLParser.isCoinOnlyReply(message: $0.message, pics: $0.pics) }
            : []
        let coinIDs = Set(coinOnlyReplies.map(\.id))
        let normalReplies = visibleReplies.filter { !coinIDs.contains($0.id) }

        LazyVStack(alignment: .leading, spacing: 10) {
            if !coinOnlyReplies.isEmpty {
                DisclosureGroup("已折叠 \(coinOnlyReplies.count) 条酷币表情评论", isExpanded: $viewModel.isCoinRepliesExpanded) {
                    VStack(spacing: 10) {
                        ForEach(coinOnlyReplies) { reply in
                            replyRow(reply, feed: feed)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(14)
                .c001CardStyle(cornerRadius: 16)
                .padding(.horizontal, 12)
            }

            if viewModel.isLoadingReplies && visibleReplies.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if normalReplies.isEmpty && coinOnlyReplies.isEmpty {
                ContentUnavailableView("暂无评论", systemImage: "bubble.right")
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(normalReplies.enumerated()), id: \.element.id) { index, reply in
                    replyRow(reply, feed: feed)
                        .onAppear {
                            if index >= normalReplies.count - 4 {
                                Task { await viewModel.loadMoreReplies(appState: appState) }
                            }
                        }
                }
                if viewModel.isLoadingMoreReplies {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private func replyRow(_ reply: ReplyItem, feed: FeedItem) -> some View {
        let replyAvatarID = "reply-avatar-\(detailSeed)-\(reply.id)"
        return SwipeableReplyCard(
            onReply: {
                if appState.accounts.isLoggedIn {
                    appState.composeMode = .replyToComment(targetID: reply.id, replyToName: reply.username)
                } else {
                    appState.showLoginSheet = true
                }
            },
            onLike: {
                Task { await viewModel.toggleReplyLike(reply, appState: appState) }
            },
            isLiked: reply.isLiked,
            onCopy: {
                UIPasteboard.general.string = FeedHTMLParser.plainText(reply.message)
                appState.showToast("已复制评论")
            }
        ) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    if !reply.uid.isEmpty {
                        appState.push(.user(uid: reply.uid, transitionID: replyAvatarID))
                    }
                } label: {
                    AvatarView(url: reply.avatar, size: 36)
                        .applyZoomSource(id: replyAvatarID, in: zoomNamespace)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(reply.username)
                            .font(.subheadline.weight(.semibold))
                        if reply.uid == feed.uid || reply.isAuthor {
                            badgeLabel("楼主", color: Color.accentColor)
                        }
                        if reply.isTop {
                            badgeLabel("置顶", color: .orange)
                        }
                        Spacer()
                        GlassEffectContainer(spacing: 6) {
                            HStack(spacing: 6) {
                                Button {
                                    if appState.accounts.isLoggedIn {
                                        appState.composeMode = .replyToComment(targetID: reply.id, replyToName: reply.username)
                                    } else {
                                        appState.showLoginSheet = true
                                    }
                                } label: {
                                    Image(systemName: "bubble.right")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                        .foregroundStyle(Color.secondary)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    Task { await viewModel.toggleReplyLike(reply, appState: appState) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: reply.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                        if reply.likeNum > 0 { Text("\(reply.likeNum)").monospacedDigit() }
                                    }
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                                    .foregroundStyle(reply.isLiked ? Color.pink : Color.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    RichTextView(
                        html: reply.message,
                        fontSize: 15 * appState.settings.fontScale,
                        showEmoji: appState.settings.showEmoji,
                        isSelectableText: false,
                        onLinkTap: { link in
                            appState.openRawLink(link)
                        },
                        onCardTap: {
                            if appState.accounts.isLoggedIn {
                                appState.composeMode = .replyToComment(targetID: reply.id, replyToName: reply.username)
                            } else {
                                appState.showLoginSheet = true
                            }
                        }
                    )

                    if !reply.mediaItems.isEmpty {
                        MediaGridView(items: reply.mediaItems)
                    }

                    if !reply.nested.isEmpty || reply.replyNum > 0 {
                        Button {
                            selectedReplyForThread = reply
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(reply.nested.prefix(3)) { sub in
                                    Text("\(sub.username)：\(FeedHTMLParser.plainText(sub.message))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if reply.replyNum > reply.nested.count || reply.replyNum > 0 {
                                    HStack(spacing: 4) {
                                        Text("查看全部 \(reply.replyNum) 条回复")
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    let meta = [Formatting.relativeTime(reply.dateline, fallback: reply.datelineText), reply.ipLocation]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                if appState.accounts.isLoggedIn {
                    appState.composeMode = .replyToComment(targetID: reply.id, replyToName: reply.username)
                } else {
                    appState.showLoginSheet = true
                }
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = FeedHTMLParser.plainText(reply.message)
                    appState.showToast("已复制评论")
                } label: {
                    Label("复制评论", systemImage: "doc.on.doc")
                }
                if feed.uid == appState.accounts.activeUID {
                    Button {
                        Task { await viewModel.togglePinReply(reply, appState: appState) }
                    } label: {
                        Label(reply.isTop ? "取消置顶" : "置顶评论", systemImage: reply.isTop ? "pin.slash" : "pin")
                    }
                }
                if reply.uid == appState.accounts.activeUID {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteReply(reply, appState: appState) }
                    } label: {
                        Label("删除评论", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func badgeLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private func bottomInteractionBar(_ feed: FeedItem) -> some View {
        let isBookmarked = appState.accounts.isLoggedIn
            ? feed.isFavorited
            : appState.historyAndFav.isLocallyFavorited(id: feed.id)

        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if appState.accounts.isLoggedIn {
                        appState.composeMode = .replyToFeed(feedID: feed.id, authorName: feed.username)
                    } else {
                        appState.showLoginSheet = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.right")
                        Text("写评论…")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await viewModel.toggleLike(appState: appState) }
                } label: {
                    Image(systemName: feed.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(feed.isLiked ? Color.pink : Color.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(flexibility: .soft), trigger: feed.isLiked)

                Button {
                    Task { await viewModel.toggleCollect(appState: appState) }
                } label: {
                    Image(systemName: isBookmarked ? "star.fill" : "star")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isBookmarked ? Color.orange : Color.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)

                Button {
                    if appState.accounts.isLoggedIn {
                        appState.composeMode = .forward(feed)
                    } else {
                        appState.showLoginSheet = true
                    }
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func startExport(feed: FeedItem, format: ExportFormat) async {
        isExporting = true
        defer { isExporting = false }
        do {
            let result = try await ExportCoordinator.prepareExport(
                feed: feed,
                format: format,
                filterService: appState.contentFilter,
                blockedUIDs: appState.blacklist.blockedUserSet
            )
            if result.warnings.isEmpty {
                shareURL = result.fileURL
            } else {
                pendingExport = result
                showExportWarningAlert = true
            }
        } catch {
            appState.showToast("导出失败：\(error.localizedDescription)")
        }
    }
}

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
