import CoolapkKit
import SwiftUI
import UIKit

public struct SwipeDeckView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var viewModel = SwipeDeckViewModel()
    @State private var deckPhase: CGFloat = 0
    @State private var dragProgress: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var canDragCardFromStart = false
    @State private var lastDragEndedAt: Date = .distantPast
    @State private var shareFileURL: URL?

    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    appState.settings.accentColor.opacity(0.06),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if viewModel.isLoading && viewModel.cards.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在聚合全站图文动态…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let error = viewModel.errorMessage, viewModel.cards.isEmpty {
                ContentUnavailableView {
                    Label("暂无图集动态", systemImage: "rectangle.stack.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重新抽取") {
                        Task { await reloadDeck(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.cards.isEmpty {
                ContentUnavailableView("正在准备推荐卡片", systemImage: "rectangle.stack")
            } else {
                GeometryReader { geo in
                    let cardWidth = min(max(geo.size.width - 42, 272), 404)
                    let cardHeight = min(max(geo.size.height - 54, 410), max(430, geo.size.height * 0.83))
                    let mediaHeight = floor(cardHeight * 0.67)
                    let currentCard = viewModel.cards[safe: viewModel.currentIndex]
                    let stagePhase = clampedPhase(maxIndex: max(0, viewModel.cards.count - 1))
                    let baseSlot = Int(floor(stagePhase))
                    let lowSlot = max(0, baseSlot - 1)
                    let highSlot = min(max(0, viewModel.cards.count - 1), baseSlot + 2)
                    let visibleSlots = !viewModel.cards.isEmpty && lowSlot <= highSlot ? Array(lowSlot...highSlot) : []
                    let mediaHitZone = CGRect(x: 12, y: 12, width: max(120, cardWidth - 24), height: max(120, mediaHeight - 12))

                    ZStack {
                        ForEach(visibleSlots, id: \.self) { index in
                            let card = viewModel.cards[index]
                            SwipeFeedCardItemView(
                                card: card,
                                cardWidth: cardWidth,
                                cardHeight: cardHeight,
                                mediaHeight: mediaHeight,
                                onOpenFeed: {
                                    guard Date().timeIntervalSince(lastDragEndedAt) > 0.25 else { return }
                                    openFeedDetail(card.feed, transitionID: "swipe-card-\(card.id)")
                                },
                                onToggleLike: {
                                    Task { await viewModel.toggleLike(for: card.id, appState: appState) }
                                },
                                onShareFile: { url in
                                    shareFileURL = url
                                }
                            )
                            .id(card.id)
                            .modifier(SwipeCardOrbitalMotionModifier(
                                phase: stagePhase,
                                slot: index,
                                cardWidth: cardWidth
                            ))
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .offset(y: -12)
                        .coordinateSpace(name: "SwipeCardStageSpace")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .named("SwipeCardStageSpace"))
                            .onChanged { value in
                                guard !viewModel.cards.isEmpty else { return }
                                if !isHorizontalDragging && !canDragCardFromStart {
                                    // Inside a multi-photo stacked image zone, let the inner PhotoStackCardView own horizontal swipes.
                                    if let card = currentCard,
                                       card.feed.mediaItems.count > 1,
                                       mediaHitZone.contains(value.startLocation) {
                                        canDragCardFromStart = false
                                        return
                                    }
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    if abs(dx) > max(10, abs(dy) * 1.15) {
                                        canDragCardFromStart = true
                                        isHorizontalDragging = true
                                    }
                                }

                                guard canDragCardFromStart else { return }
                                let dx = value.translation.width
                                let rawStep = -dx / max(220, cardWidth * 0.72)
                                if deckPhase <= 0.01 && rawStep < 0 {
                                    dragProgress = max(-0.26, rawStep * 0.35)
                                } else if Int(deckPhase.rounded()) >= viewModel.cards.count - 1 && rawStep > 0 {
                                    dragProgress = min(0.26, rawStep * 0.35)
                                } else {
                                    dragProgress = max(-1.15, min(1.15, rawStep))
                                }
                            }
                            .onEnded { value in
                                defer {
                                    isHorizontalDragging = false
                                    canDragCardFromStart = false
                                }
                                guard canDragCardFromStart else {
                                    dragProgress = 0
                                    return
                                }
                                lastDragEndedAt = Date()

                                let dx = value.translation.width
                                let predicted = value.predictedEndTranslation.width
                                let base = Int(deckPhase.rounded())
                                var targetIndex = base
                                if dx < -48 || predicted < -110 {
                                    targetIndex = min(viewModel.cards.count - 1, base + 1)
                                } else if dx > 48 || predicted > 110 {
                                    targetIndex = max(0, base - 1)
                                }

                                let currentCombined = clampedPhase(maxIndex: max(0, viewModel.cards.count - 1))
                                deckPhase = currentCombined
                                dragProgress = 0
                                withAnimation(.interpolatingSpring(stiffness: 210, damping: 24)) {
                                    deckPhase = CGFloat(targetIndex)
                                }
                                viewModel.currentIndex = targetIndex
                                Task { await viewModel.loadMoreIfNeeded(appState: appState) }
                            }
                    )
                }
            }
        }
        .navigationTitle("刷动态")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("聚合范围", selection: $viewModel.sourceMode) {
                        ForEach(SwipeDeckSourceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(viewModel.sourceMode.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.currentIndex > 0 {
                    Button {
                        stepDeck(by: -1)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel("上一条")
                }

                Button {
                    Task { await reloadDeck(force: true) }
                } label: {
                    if viewModel.isLoading || viewModel.isLoadingMore {
                        ProgressView()
                    } else {
                        Image(systemName: "shuffle")
                    }
                }
                .accessibilityLabel("换一批")
            }
        }
        .sheet(item: Binding(
            get: { shareFileURL.map { SwipeShareFileItem(url: $0) } },
            set: { if $0 == nil { shareFileURL = nil } }
        )) { item in
            SwipeShareActivityView(items: [item.url])
        }
        .task(id: "\(appState.isSessionBootstrapped)|\(appState.settings.onboardingCompleted)|\(appState.sessionVersion)|\(viewModel.sourceMode.rawValue)") {
            guard appState.isSessionBootstrapped, appState.settings.onboardingCompleted else { return }
            await viewModel.reload(appState: appState, force: viewModel.cards.isEmpty)
        }
        .onChange(of: viewModel.sourceMode) { _, _ in
            guard appState.isSessionBootstrapped, appState.settings.onboardingCompleted else { return }
            Task { await reloadDeck(force: true) }
        }
        .onChange(of: appState.swipeDoubleTapTrigger) { _, _ in
            Task { await reloadDeck(force: true) }
        }
    }

    private func clampedPhase(maxIndex: Int) -> CGFloat {
        max(-0.28, min(CGFloat(maxIndex) + 0.28, deckPhase + dragProgress))
    }

    private func reloadDeck(force: Bool) async {
        deckPhase = 0
        dragProgress = 0
        await viewModel.reload(appState: appState, force: force)
    }

    private func stepDeck(by delta: Int) {
        let maxIdx = max(0, viewModel.cards.count - 1)
        let target = max(0, min(maxIdx, viewModel.currentIndex + delta))
        withAnimation(.interpolatingSpring(stiffness: 210, damping: 24)) {
            deckPhase = CGFloat(target)
        }
        viewModel.currentIndex = target
        Task { await viewModel.loadMoreIfNeeded(appState: appState) }
    }

    private func openFeedDetail(_ feed: FeedItem, transitionID: String) {
        let targetID = feed.effectiveFeedID
        guard !targetID.isEmpty else { return }
        appState.push(.feed(
            id: targetID,
            initial: targetID == feed.id ? feed : nil,
            transitionID: transitionID
        ))
    }
}

private struct SwipeFeedCardItemView: View {
    let card: SwipeFeedCard
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let mediaHeight: CGFloat
    let onOpenFeed: () -> Void
    let onToggleLike: () -> Void
    let onShareFile: (URL) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var photoDeckPhase: CGFloat = 0
    @State private var transitionSeed = UUID().uuidString

    var body: some View {
        let feed = card.feed
        let items = feed.mediaItems

        VStack(spacing: 0) {
            // Top ~67%: Image / Orbital stacked images container
            ZStack(alignment: .topLeading) {
                if items.count > 1 {
                    PhotoStackCardView(
                        items: items,
                        deckPhase: $photoDeckPhase,
                        transitionSeed: transitionSeed,
                        enableZoomSource: true,
                        disableHDR: appState.settings.disableHDR,
                        cardHeight: max(200, mediaHeight - 32),
                        cornerRadius: 20,
                        adaptiveContentMode: true,
                        adaptivePerItemAspect: false,
                        initialWidth: max(180, cardWidth - 24),
                        onTapCard: { idx in
                            appState.openMedia(items, at: idx, sourcePrefix: "media-\(transitionSeed)")
                        },
                        contextMenuBuilder: { item, idx in
                            MediaActionsContextMenu(
                                item: item,
                                onViewFull: {
                                    appState.openMedia(items, at: idx, sourcePrefix: "media-\(transitionSeed)")
                                },
                                onShareFile: onShareFile
                            )
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                } else if let first = items.first {
                    singlePortraitMedia(item: first)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                }

                // Subtle source badge top-left inside photo section
                Text(card.sourceLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .foregroundStyle(.primary)
                    .padding(.leading, items.count > 2 ? 32 : 22)
                    .padding(.top, 22)
                    .allowsHitTesting(false)
            }
            .frame(height: mediaHeight)

            // Bottom ~33%: Concise feed metadata + drag-friendly area
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        if !feed.uid.isEmpty {
                            appState.push(.user(
                                uid: feed.uid,
                                initialUsername: feed.username,
                                initialAvatar: feed.avatar
                            ))
                        }
                    } label: {
                        HStack(spacing: 8) {
                            AvatarView(url: feed.avatar, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(feed.username.isEmpty ? "匿名酷友" : feed.username)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text([Formatting.relativeTime(feed.dateline, fallback: feed.datelineText), feed.deviceTitle]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    if let firstTag = feed.relationEntities.first {
                        Button {
                            if !firstTag.url.isEmpty {
                                appState.openRawLink(firstTag.url)
                            } else {
                                appState.push(.topic(tag: firstTag.title))
                            }
                        } label: {
                            Text(TopicItem.cleanTitle(firstTag.title))
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if !feed.messageTitle.isEmpty {
                        Text(feed.messageTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if !card.plainSummary.isEmpty {
                        Text(card.plainSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(feed.messageTitle.isEmpty ? 3 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenFeed)

                Spacer(minLength: 0)

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: onToggleLike) {
                            HStack(spacing: 4) {
                                Image(systemName: feed.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                Text(feed.likeNum > 0 ? Formatting.count(feed.likeNum) : "赞")
                                    .monospacedDigit()
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(feed.isLiked ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)

                        Button(action: onOpenFeed) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.right")
                                Text(feed.replyNum > 0 ? Formatting.count(feed.replyNum) : "评论")
                                    .monospacedDigit()
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)

                        Button {
                            appState.favoritePickerFeed = feed
                        } label: {
                            Image(systemName: feed.isFavorited ? "star.fill" : "star")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(feed.isFavorited ? Color.orange : Color.primary)
                                .frame(width: 30, height: 28)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        Button(action: onOpenFeed) {
                            HStack(spacing: 3) {
                                Text("详情")
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: cardWidth, height: cardHeight)
        .c001CardStyle(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
        }
        .applyZoomSource(id: "swipe-card-\(card.id)", in: zoomNamespace, cornerRadius: 28)
    }

    @ViewBuilder
    private func singlePortraitMedia(item: FeedMedia) -> some View {
        let ratio = MediaGridView.inferredAspectRatio(from: item.thumbnailUrl)
        let shouldLetterboxWide = (ratio ?? 1.0) > 1.38
        let containerH = max(220, mediaHeight - 16)
        let isLong = (ratio ?? 1.0) < 0.44
        let showLive = item.isLivePhoto || ImagePipeline.cachedLiveFlagSync(urlString: item.sourceUrl)
        let showHDR = item.isHdr || ImagePipeline.cachedHDRFlagSync(urlString: item.sourceUrl)

        ZStack(alignment: .topTrailing) {
            Color(.secondarySystemGroupedBackground)
                .frame(height: containerH)
                .overlay {
                    if shouldLetterboxWide {
                        ZStack {
                            RemoteImageView(url: item.thumbnailUrl, maxPixelSize: 120, contentMode: .fill)
                                .blur(radius: 14)
                                .opacity(0.45)
                            RemoteImageView(url: item.sourceUrl, maxPixelSize: 960, contentMode: .fit)
                        }
                    } else {
                        RemoteImageView(url: item.sourceUrl, maxPixelSize: 960, contentMode: .fill)
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                .applyZoomSource(id: "swipe-single-\(transitionSeed)-0", in: zoomNamespace, cornerRadius: 20)
                .onTapGesture {
                    appState.openMedia([item], at: 0, sourcePrefix: "swipe-single-\(transitionSeed)")
                }
                .contextMenu {
                    MediaActionsContextMenu(
                        item: item,
                        onViewFull: {
                            appState.openMedia([item], at: 0, sourcePrefix: "swipe-single-\(transitionSeed)")
                        },
                        onShareFile: onShareFile
                    )
                } preview: {
                    MediaContextMenuPreview(item: item, disableHDR: appState.settings.disableHDR)
                }

            if showLive || showHDR || item.isGif || isLong {
                HStack(spacing: 4) {
                    if showLive {
                        HStack(spacing: 2) {
                            Image(systemName: "livephoto")
                            Text("Live")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .capsule)
                    }
                    if showHDR {
                        Text("HDR")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                    if item.isGif {
                        Text("GIF")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                    if isLong {
                        Text("长图")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
                .padding(10)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct SwipeCardOrbitalMotionModifier: ViewModifier, @MainActor Animatable {
    var phase: CGFloat
    let slot: Int
    let cardWidth: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        let t = CGFloat(slot) - phase
        let isFront = abs(t) < 0.35
        let geometry = cardGeometry(for: t)

        content
            .scaleEffect(geometry.scale)
            .rotationEffect(.degrees(geometry.angle))
            .offset(x: geometry.x, y: geometry.y)
            .opacity(geometry.opacity)
            .zIndex(geometry.zIndex)
            .allowsHitTesting(isFront)
    }

    private struct CardGeometry {
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat
        let angle: Double
        let opacity: Double
        let zIndex: Double
    }

    private func cardGeometry(for t: CGFloat) -> CardGeometry {
        if t < 0 {
            if t >= -1.0 {
                let p = -t
                let swingOut = sin(p * .pi)
                let tuckRatio = min(1.0, max(0.0, (p - 0.5) * 2.0))
                let x = (-swingOut * cardWidth * 0.72) + (tuckRatio * -18)
                let y = (p * 12.0) + (tuckRatio * 4.0)
                let scale = 1.0 - (0.06 * p)
                let angle = Double(-swingOut * 9.5) + (Double(tuckRatio) * -4.2)
                let zIndex: Double = p < 0.48 ? 100.0 : 40.0
                let opacity = 1.0 - Double(tuckRatio) * 0.12
                return CardGeometry(x: x, y: y, scale: scale, angle: angle, opacity: opacity, zIndex: zIndex)
            } else {
                let recede = min(1.0, max(0.0, -t - 1.0))
                return CardGeometry(
                    x: -18 - recede * 8,
                    y: 16 + recede * 8,
                    scale: 0.94 - recede * 0.05,
                    angle: -4.2 - Double(recede) * 2.2,
                    opacity: max(0.0, 0.88 * (1.0 - Double(recede))),
                    zIndex: 20.0 - Double(recede)
                )
            }
        } else {
            let capped = min(2.0, t)
            let fade = t <= 1.2 ? 1.0 : max(0.0, 1.0 - Double((t - 1.2) / 0.8))
            return CardGeometry(
                x: capped * 17.0,
                y: capped * 18.0,
                scale: 1.0 - capped * 0.058,
                angle: Double(capped) * 4.2,
                opacity: t <= 1.0 ? 1.0 - Double(capped) * 0.04 : 0.96 * fade,
                zIndex: 80.0 - Double(capped) * 15.0
            )
        }
    }
}

private struct SwipeShareFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SwipeShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
