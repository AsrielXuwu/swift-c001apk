import CoolapkKit
import ImageIO
import os
import Photos
import PhotosUI
import SwiftUI
import UIKit

public struct MediaGridView: View {
    public let items: [FeedMedia]
    public var onTapItem: ((Int) -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.suppressMediaTap) private var suppressMediaTap
    @Environment(\.mediaOpenAction) private var mediaOpenAction
    @State private var transitionSeed = UUID().uuidString
    @State private var deckPhase: CGFloat = 0
    @State private var shareFileURL: URL?

    public init(items: [FeedMedia], onTapItem: ((Int) -> Void)? = nil) {
        self.items = items
        self.onTapItem = onTapItem
    }

    public var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else if items.count == 1 {
                singleImage(items[0], index: 0)
            } else if appState.settings.mediaDisplayStyle == .stackedCards {
                PhotoStackCardView(
                    items: items,
                    deckPhase: $deckPhase,
                    transitionSeed: transitionSeed,
                    enableZoomSource: onTapItem == nil,
                    disableHDR: appState.settings.disableHDR,
                    onTapCard: { idx in triggerTap(at: idx) },
                    onShareFile: { shareFileURL = $0 },
                    contextMenuBuilder: { item, idx in
                        mediaContextMenu(item: item, index: idx)
                    }
                )
            } else {
                gridView(items)
            }
        }
        .sheet(item: Binding(
            get: { shareFileURL.map { MediaShareFileItem(url: $0) } },
            set: { if $0 == nil { shareFileURL = nil } }
        )) { shareItem in
            MediaShareActivityView(items: [shareItem.url])
        }
    }

    private func gridView(_ items: [FeedMedia]) -> some View {
        let displayItems = Array(items.prefix(9))
        let columnCount = displayItems.count == 2 || displayItems.count == 4 ? 2 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: columnCount)

        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(displayItems.enumerated()), id: \.offset) { index, item in
                let sourceID = onTapItem == nil ? "media-\(transitionSeed)-\(index)" : nil
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            RemoteImageView(
                                url: item.thumbnailUrl,
                                maxPixelSize: 420
                            )
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 14)
                        .onTapGesture {
                            triggerTap(at: index)
                        }
                        .contextMenu {
                            mediaContextMenu(item: item, index: index)
                        } preview: {
                            MediaContextMenuPreview(item: item, disableHDR: appState.settings.disableHDR)
                        }

                    badgeStack(for: item)

                    if index == 8 && items.count > 9 {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.45))
                            .overlay {
                                Text("+\(items.count - 9)")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func triggerTap(at index: Int) {
        guard !suppressMediaTap else { return }
        let prefix = "media-\(transitionSeed)"
        if let onTapItem {
            onTapItem(index)
        } else if let mediaOpenAction {
            mediaOpenAction(items, index, prefix)
        } else {
            appState.openMedia(items, at: index, sourcePrefix: prefix)
        }
    }

    private func singleImage(_ item: FeedMedia, index: Int) -> some View {
        let ratio = Self.inferredAspectRatio(from: item.thumbnailUrl) ?? 1.45
        let clampedRatio = max(0.45, min(ratio, 2.2))
        let maxW: CGFloat = 310
        let targetWidth: CGFloat = clampedRatio >= 1.0 ? maxW : min(maxW, max(165, 240 * clampedRatio))
        let targetHeight: CGFloat = min(300, max(120, targetWidth / clampedRatio))
        let sourceID = onTapItem == nil ? "media-\(transitionSeed)-\(index)" : nil

        return ZStack(alignment: .topTrailing) {
            RemoteImageView(
                url: item.thumbnailUrl,
                maxPixelSize: 1080,
                contentMode: .fill,
                honorHDR: false
            )
            .frame(width: targetWidth, height: targetHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 16)
            .onTapGesture {
                triggerTap(at: index)
            }
            .contextMenu {
                mediaContextMenu(item: item, index: index)
            } preview: {
                MediaContextMenuPreview(item: item, disableHDR: appState.settings.disableHDR)
            }

            badgeStack(for: item, isLong: (ratio < 0.44))
        }
    }

    @ViewBuilder
    private func mediaContextMenu(item: FeedMedia, index: Int) -> some View {
        MediaActionsContextMenu(
            item: item,
            onViewFull: { triggerTap(at: index) },
            onShareFile: { shareFileURL = $0 }
        )
    }
}

public struct MediaActionsContextMenu: View {
    public let item: FeedMedia
    public let onViewFull: () -> Void
    public let onShareFile: (URL) -> Void

    @Environment(AppState.self) private var appState

    public init(
        item: FeedMedia,
        onViewFull: @escaping () -> Void,
        onShareFile: @escaping (URL) -> Void
    ) {
        self.item = item
        self.onViewFull = onViewFull
        self.onShareFile = onShareFile
    }

    public var body: some View {
        Button {
            onViewFull()
        } label: {
            Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            Task { await Self.saveImageToPhotos(item, appState: appState) }
        } label: {
            Label("保存到相册", systemImage: "square.and.arrow.down")
        }

        Button {
            Task { await Self.copyImageToPasteboard(item, appState: appState) }
        } label: {
            Label("复制图片", systemImage: "doc.on.doc")
        }

        Button {
            UIPasteboard.general.string = item.sourceUrl
            appState.showToast("已复制图片链接")
        } label: {
            Label("复制图片链接", systemImage: "link")
        }

        Button {
            Task { await Self.shareImageFile(item, appState: appState, onShareFile: onShareFile) }
        } label: {
            Label("分享图片", systemImage: "square.and.arrow.up")
        }
    }

    @MainActor
    public static func shareImageFile(
        _ item: FeedMedia,
        appState: AppState,
        onShareFile: @escaping (URL) -> Void
    ) async {
        if let temp = await ImagePipeline.shared.downloadToTemporaryFile(
            urlString: item.sourceUrl,
            defaultExtension: item.isGif ? "gif" : "jpg"
        ) {
            onShareFile(temp)
        } else {
            appState.showToast("准备分享文件失败")
        }
    }

    @MainActor
    public static func saveImageToPhotos(_ item: FeedMedia, appState: AppState) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            appState.showToast("请在系统设置中允许访问相册")
            return
        }
        guard let tempURL = await ImagePipeline.shared.downloadToTemporaryFile(
            urlString: item.sourceUrl,
            defaultExtension: item.isGif ? "gif" : "jpg"
        ) else {
            appState.showToast("图片下载失败")
            return
        }
        let videoTemp: URL? = if let videoUrl = item.videoUrl, !videoUrl.isEmpty {
            await ImagePipeline.shared.downloadToTemporaryFile(urlString: videoUrl, defaultExtension: "mov")
        } else {
            nil
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, fileURL: tempURL, options: nil)
                if let videoTemp {
                    req.addResource(with: .pairedVideo, fileURL: videoTemp, options: nil)
                }
            }
            appState.showToast(videoTemp != nil ? "已保存实况照片到相册" : "已保存到相册")
        } catch {
            appState.showToast("保存失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    public static func copyImageToPasteboard(_ item: FeedMedia, appState: AppState) async {
        if let loaded = await ImagePipeline.shared.loadImage(urlString: item.sourceUrl, maxPixelSize: nil) {
            UIPasteboard.general.image = loaded.image
            appState.showToast("已复制图片")
        } else {
            appState.showToast("图片读取失败")
        }
    }
}

extension MediaGridView {

    @ViewBuilder
    private func badgeStack(for item: FeedMedia, isLong: Bool = false) -> some View {
        let showLive = item.isLivePhoto
            || ImagePipeline.cachedLiveFlagSync(urlString: item.sourceUrl)
            || ImagePipeline.cachedLiveFlagSync(urlString: item.thumbnailUrl)
        let showHDR = item.isHdr
            || ImagePipeline.cachedHDRFlagSync(urlString: item.sourceUrl)
            || ImagePipeline.cachedHDRFlagSync(urlString: item.thumbnailUrl)
        let showGIF = item.isGif

        if showLive || showHDR || showGIF || isLong {
            HStack(spacing: 4) {
                if showLive {
                    HStack(spacing: 2) {
                        Image(systemName: "livephoto")
                        Text("Live")
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(.regular, in: .capsule)
                    .foregroundStyle(.primary)
                }
                if showHDR { badgePill("HDR") }
                if showGIF { badgePill("GIF") }
                if isLong { badgePill("长图") }
            }
            .padding(6)
            .allowsHitTesting(false)
        }
    }

    private func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular, in: .capsule)
            .foregroundStyle(.primary)
    }

    public static func inferredAspectRatio(from urlString: String) -> CGFloat? {
        let pattern = #"[_@](\d{2,5})x(\d{2,5})(?:\D|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)),
              let wRange = Range(match.range(at: 1), in: urlString),
              let hRange = Range(match.range(at: 2), in: urlString),
              let w = Double(urlString[wRange]),
              let h = Double(urlString[hRange]),
              w > 0, h > 0 else {
            return nil
        }
        return CGFloat(w / h)
    }
}

public struct PhotoStackCardView<MenuContent: View>: View {
    public let items: [FeedMedia]
    @Binding public var deckPhase: CGFloat
    public let transitionSeed: String
    public let enableZoomSource: Bool
    public let disableHDR: Bool
    public var cardHeight: CGFloat = 218
    public var cornerRadius: CGFloat = 18
    public var adaptiveContentMode: Bool = false
    public var adaptivePerItemAspect: Bool = true
    public var initialWidth: CGFloat? = nil
    public let onTapCard: (Int) -> Void
    public var onShareFile: ((URL) -> Void)? = nil
    @ViewBuilder public let contextMenuBuilder: (FeedMedia, Int) -> MenuContent

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.replySwipeLock) private var replySwipeLock
    @Environment(\.replyCardCoordinateSpace) private var replyCardCoordinateSpace
    @State private var dragProgress: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var isPreviewLifted = false
    @State private var lastDragEndedAt: Date = .distantPast
    @State private var availableWidth: CGFloat
    @State private var detectedRatios: [Int: CGFloat] = [:]

    public init(
        items: [FeedMedia],
        deckPhase: Binding<CGFloat>,
        transitionSeed: String,
        enableZoomSource: Bool,
        disableHDR: Bool,
        cardHeight: CGFloat = 218,
        cornerRadius: CGFloat = 18,
        adaptiveContentMode: Bool = false,
        adaptivePerItemAspect: Bool = true,
        initialWidth: CGFloat? = nil,
        onTapCard: @escaping (Int) -> Void,
        onShareFile: ((URL) -> Void)? = nil,
        @ViewBuilder contextMenuBuilder: @escaping (FeedMedia, Int) -> MenuContent
    ) {
        self.items = items
        self._deckPhase = deckPhase
        self.transitionSeed = transitionSeed
        self.enableZoomSource = enableZoomSource
        self.disableHDR = disableHDR
        self.cardHeight = cardHeight
        self.cornerRadius = cornerRadius
        self.adaptiveContentMode = adaptiveContentMode
        self.adaptivePerItemAspect = adaptivePerItemAspect
        self.initialWidth = initialWidth
        self._availableWidth = State(initialValue: initialWidth ?? 320)
        self.onTapCard = onTapCard
        self.onShareFile = onShareFile
        self.contextMenuBuilder = contextMenuBuilder
    }

    private var currentNearestIndex: Int {
        let count = items.count
        guard count > 0 else { return 0 }
        let rounded = Int((deckPhase + dragProgress).rounded())
        return ((rounded % count) + count) % count
    }

    private func ratioForItem(at index: Int) -> CGFloat? {
        guard items.indices.contains(index) else { return nil }
        if let detected = detectedRatios[index] { return detected }
        let item = items[index]
        return MediaGridView.inferredAspectRatio(from: item.sourceUrl)
            ?? MediaGridView.inferredAspectRatio(from: item.thumbnailUrl)
    }

    private func cardFrame(at index: Int, maxStageWidth: CGFloat) -> CGSize {
        guard adaptivePerItemAspect else {
            return CGSize(width: maxStageWidth, height: cardHeight)
        }
        let rawRatio = ratioForItem(at: index) ?? 1.28
        let maxH: CGFloat = 336
        let clamped = max(0.50, min(rawRatio, 2.25))
        let naturalH = maxStageWidth / clamped
        let finalH = min(maxH, max(140, naturalH))
        let finalW = min(maxStageWidth, max(140, finalH * clamped))
        return CGSize(width: finalW, height: finalH)
    }

    public var body: some View {
        let count = items.count
        let visibleLayers = min(count, 3)
        let activeIdx = currentNearestIndex
        let activeItem = items[activeIdx]
        let leftInset: CGFloat = visibleLayers > 2 ? 16 : 0
        let rightInset: CGFloat = visibleLayers > 1 ? 20 : 0
        let bottomInset: CGFloat = visibleLayers > 1 ? 16 : 0
        let innerStageWidth = max(160, availableWidth - leftInset - rightInset)
        let activeCardSize = cardFrame(at: activeIdx, maxStageWidth: innerStageWidth)
        let maxCardHeight: CGFloat = adaptivePerItemAspect
            ? ((0..<count).map { cardFrame(at: $0, maxStageWidth: innerStageWidth).height }.max() ?? activeCardSize.height)
            : cardHeight
        let activeRatio = ratioForItem(at: activeIdx)

        ZStack {
            let centerSlot = Int((deckPhase + dragProgress).rounded())
            OrbitalDeckStage(
                phase: deckPhase + dragProgress,
                count: count,
                cardHeight: maxCardHeight,
                isFrontLifted: isPreviewLifted
            ) { itemIndex, isFront, rawSlot in
                let item = items[itemIndex]
                let itemSize = cardFrame(at: itemIndex, maxStageWidth: innerStageWidth)
                // Keep sourceID completely invariant across active & adjacent slots (centerSlot - 1 ... centerSlot + 1)
                // so neither _ConditionalContent branch switching nor matchedTransitionSource ID mutation
                // ever occurs when isFront toggles at abs(t) < 0.35 during a swipe.
                let isPrimarySlot: Bool = {
                    if count >= 5 { return true }
                    if count == 4 { return rawSlot >= centerSlot - 1 && rawSlot <= centerSlot + 2 }
                    if count == 3 { return rawSlot >= centerSlot - 1 && rawSlot <= centerSlot + 1 }
                    if count == 2 { return rawSlot == centerSlot || rawSlot == centerSlot + 1 }
                    return true
                }()
                let sourceID = enableZoomSource
                    ? (isPrimarySlot ? "media-\(transitionSeed)-\(itemIndex)" : "media-\(transitionSeed)-slot-\(rawSlot)")
                    : nil

                if count == 1 {
                    deckCardSurface(at: itemIndex, size: itemSize)
                        .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: cornerRadius)
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .contextMenu {
                            contextMenuBuilder(item, itemIndex)
                        } preview: {
                            MediaContextMenuPreview(item: item, disableHDR: disableHDR)
                        }
                        .onTapGesture {
                            guard isFront,
                                  !isHorizontalDragging,
                                  abs(dragProgress) < 0.04,
                                  Date().timeIntervalSince(lastDragEndedAt) > 0.30 else { return }
                            onTapCard(itemIndex)
                        }
                } else {
                    deckCardSurface(at: itemIndex, size: itemSize)
                        .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: cornerRadius)
                        .onTapGesture {
                            guard isFront,
                                  !isHorizontalDragging,
                                  abs(dragProgress) < 0.04,
                                  Date().timeIntervalSince(lastDragEndedAt) > 0.30 else { return }
                            onTapCard(itemIndex)
                        }
                }
            }
            .padding(.leading, leftInset)
            .padding(.trailing, rightInset)
            .padding(.bottom, bottomInset)

            if count > 1 {
                let shouldLetterboxActive = adaptiveContentMode && (activeRatio ?? 1.0) > 1.38
                HorizontalDeckPanOverlay(
                    isEnabled: count > 1,
                    activeCardSize: activeCardSize,
                    previewConfig: DeckContextPreviewConfig(
                        activeItem: activeItem,
                        cornerRadius: cornerRadius,
                        adaptiveContentMode: adaptiveContentMode,
                        shouldLetterboxWide: shouldLetterboxActive,
                        disableHDR: disableHDR,
                        appState: appState,
                        onPreviewLiftedChanged: { _ in
                            // Keep the front card in OrbitalDeckStage visible at its original position
                            // so it never vanishes or flickers before/during the context menu preview transition.
                            if isPreviewLifted {
                                isPreviewLifted = false
                            }
                        },
                        onShareFile: onShareFile
                    ),
                    onTap: {
                        guard !isHorizontalDragging,
                              abs(dragProgress) < 0.04,
                              Date().timeIntervalSince(lastDragEndedAt) > 0.30 else { return }
                        onTapCard(activeIdx)
                    },
                    onDragChanged: { dx in
                        if !isHorizontalDragging {
                            isHorizontalDragging = true
                            replySwipeLock?.setDraggingMedia(true)
                        }
                        dragProgress = max(-1.15, min(1.15, -dx / 210.0))
                    },
                    onDragEnded: { dx, predicted, cancelled in
                        lastDragEndedAt = Date()
                        isHorizontalDragging = false
                        replySwipeLock?.setDraggingMedia(false)
                        guard !cancelled else {
                            withAnimation(.interpolatingSpring(stiffness: 240, damping: 26)) {
                                dragProgress = 0
                            }
                            return
                        }
                        let deltaStep: CGFloat
                        if dx < -38 || predicted < -85 {
                            deltaStep = 1
                        } else if dx > 38 || predicted > 85 {
                            deltaStep = -1
                        } else {
                            deltaStep = 0
                        }
                        let combined = deckPhase + dragProgress
                        let base = deckPhase.rounded()
                        deckPhase = combined
                        dragProgress = 0
                        withAnimation(.interpolatingSpring(stiffness: 220, damping: 24)) {
                            deckPhase = base + deltaStep
                        }
                    }
                )
                .frame(width: activeCardSize.width, height: activeCardSize.height)
                .padding(.leading, leftInset)
                .padding(.trailing, rightInset)
                .padding(.bottom, bottomInset)
            }

            // Stationary floating controls anchored cleanly to the active front card size.
            VStack {
                let showStackLive = activeItem.isLivePhoto
                    || ImagePipeline.cachedLiveFlagSync(urlString: activeItem.sourceUrl)
                    || ImagePipeline.cachedLiveFlagSync(urlString: activeItem.thumbnailUrl)
                let showStackHDR = activeItem.isHdr
                    || ImagePipeline.cachedHDRFlagSync(urlString: activeItem.sourceUrl)
                    || ImagePipeline.cachedHDRFlagSync(urlString: activeItem.thumbnailUrl)
                let showStackLong = (activeRatio ?? 1.0) < 0.44
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        if showStackLive {
                            HStack(spacing: 2) {
                                Image(systemName: "livephoto")
                                Text("Live")
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                            .foregroundStyle(.primary)
                        }
                        if showStackHDR { stackPill("HDR") }
                        if activeItem.isGif { stackPill("GIF") }
                        if showStackLong { stackPill("长图") }
                        stackPill("\(activeIdx + 1)/\(count)")
                    }
                }
                .allowsHitTesting(false)

                Spacer()

                if count > 1 {
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                stepDeck(by: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .frame(width: 24, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                stepDeck(by: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .frame(width: 24, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
            .padding(10)
            .frame(width: activeCardSize.width, height: activeCardSize.height)
            .padding(.leading, leftInset)
            .padding(.trailing, rightInset)
            .padding(.bottom, bottomInset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: visibleLayers > 1 ? maxCardHeight + bottomInset + 2 : maxCardHeight)
        .animation(adaptivePerItemAspect ? .interpolatingSpring(stiffness: 220, damping: 24) : nil, value: activeCardSize)
        .animation(adaptivePerItemAspect ? .interpolatingSpring(stiffness: 220, damping: 24) : nil, value: maxCardHeight)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, newWidth in
            if newWidth > 80, abs(newWidth - availableWidth) > 2 {
                availableWidth = newWidth
            }
        }
        .task(id: "\(transitionSeed)-\(activeIdx)") {
            // Keep adjacent cards in both directions pre-decoded in memory cache so swiping left or right
            // immediately after a context menu preview never misses cache or flashes a blank background.
            let targetMax: CGFloat = adaptiveContentMode ? 960 : 1080
            for offset in [-2, -1, 0, 1, 2] {
                let idx = ((activeIdx + offset) % count + count) % count
                guard items.indices.contains(idx) else { continue }
                let media = items[idx]
                let url = adaptiveContentMode ? media.sourceUrl : media.thumbnailUrl
                if ImagePipeline.cachedImageSync(urlString: url, maxPixelSize: targetMax, preferHDR: false) == nil {
                    if let loaded = await ImagePipeline.shared.loadImage(urlString: url, maxPixelSize: targetMax, preferHDR: false) {
                        updateDetectedRatio(index: idx, size: loaded.image.size)
                    }
                }
            }
        }
        .background {
            if let replyCardCoordinateSpace, count > 1 {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(replyCardCoordinateSpace))
                    } action: { _, rect in
                        replySwipeLock?.updateMediaFrame(id: transitionSeed, rect: rect)
                    }
                    .onDisappear {
                        replySwipeLock?.clearMediaFrame(id: transitionSeed)
                    }
            }
        }
    }

    @ViewBuilder
    private func deckCardSurface(at itemIndex: Int, size itemSize: CGSize) -> some View {
        let item = items[itemIndex]
        let ratio = ratioForItem(at: itemIndex)
        let shouldLetterboxWide = adaptiveContentMode && (ratio ?? 1.0) > 1.38

        Color(.secondarySystemGroupedBackground)
            .frame(width: itemSize.width, height: itemSize.height)
            .overlay {
                if shouldLetterboxWide {
                    ZStack {
                        RemoteImageView(
                            url: item.thumbnailUrl,
                            maxPixelSize: 120,
                            contentMode: .fill
                        )
                        .blur(radius: 14)
                        .opacity(0.45)
                        RemoteImageView(
                            url: item.sourceUrl,
                            maxPixelSize: 960,
                            contentMode: .fit
                        ) { size in
                            updateDetectedRatio(index: itemIndex, size: size)
                        }
                    }
                } else {
                    RemoteImageView(
                        url: adaptiveContentMode ? item.sourceUrl : item.thumbnailUrl,
                        maxPixelSize: adaptiveContentMode ? 960 : 1080,
                        contentMode: .fill
                    ) { size in
                        updateDetectedRatio(index: itemIndex, size: size)
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.4)
            }
    }

    private func updateDetectedRatio(index: Int, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let ratio = size.width / size.height
        if let existing = detectedRatios[index], abs(existing - ratio) < 0.01 { return }
        detectedRatios[index] = ratio
    }

    private func stepDeck(by delta: CGFloat) {
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 24)) {
            deckPhase = deckPhase.rounded() + delta
        }
    }

    private func stackPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .foregroundStyle(.primary)
    }
}

/// Shared continuous Animatable card-deck stage supporting orbital edge crossing and smooth z-order handoff.
public struct OrbitalDeckStage<CardContent: View>: View, @MainActor Animatable {
    public var phase: CGFloat
    public let count: Int
    public let cardHeight: CGFloat
    public let isFrontLifted: Bool
    @ViewBuilder public let cardBuilder: (Int, Bool, Int) -> CardContent

    public var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    public init(
        phase: CGFloat,
        count: Int,
        cardHeight: CGFloat,
        isFrontLifted: Bool = false,
        @ViewBuilder cardBuilder: @escaping (Int, Bool) -> CardContent
    ) {
        self.phase = phase
        self.count = count
        self.cardHeight = cardHeight
        self.isFrontLifted = isFrontLifted
        self.cardBuilder = { itemIndex, isFront, _ in
            cardBuilder(itemIndex, isFront)
        }
    }

    public init(
        phase: CGFloat,
        count: Int,
        cardHeight: CGFloat,
        isFrontLifted: Bool = false,
        @ViewBuilder cardBuilder: @escaping (Int, Bool, Int) -> CardContent
    ) {
        self.phase = phase
        self.count = count
        self.cardHeight = cardHeight
        self.isFrontLifted = isFrontLifted
        self.cardBuilder = cardBuilder
    }

    public var body: some View {
        let activeRounded = Int(phase.rounded())
        // Center rawSlots around activeRounded (boundary at N + 0.5) rather than floor(phase) (boundary at N.0)
        // so starting a rightward swipe from an integer rest state or settling with spring overshoot around N.0
        // never unmounts or recreates adjacent card views.
        let rawSlots = count <= 1 ? [0] : Array((activeRounded - 2)...(activeRounded + 2))

        ZStack {
            ForEach(rawSlots, id: \.self) { rawSlot in
                let itemIndex = ((rawSlot % count) + count) % count
                let t = CGFloat(rawSlot) - phase
                let isFront = (rawSlot == activeRounded) && abs(t) < 0.35
                let geometry = cardGeometry(for: t, count: count)

                cardBuilder(itemIndex, isFront, rawSlot)
                    .scaleEffect(geometry.scale)
                    .rotationEffect(.degrees(geometry.angle))
                    .offset(x: geometry.x, y: geometry.y)
                    .opacity((isFront && isFrontLifted) ? 0 : geometry.opacity)
                    .zIndex(geometry.zIndex)
                    .allowsHitTesting(isFront)
            }
        }
        .frame(height: cardHeight)
    }

    private struct CardGeometry {
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat
        let angle: Double
        let opacity: Double
        let zIndex: Double
    }

    private func cardGeometry(for t: CGFloat, count: Int) -> CardGeometry {
        // t == 0: active front card
        // t in [-1, 0]: active card swinging out left, dropping a layer around -0.48, landing in back-left slot
        // t in [-2, -1]: back-left card smoothly fading out as it recedes
        // t in [0, 1]: back-right card rising into center front
        // t in [1, 2]: newly queued card fading in smoothly into the back-right slot
        if t < 0 {
            if t >= -1.0 {
                let p = -t
                let swingOut = sin(p * .pi)
                let tuckRatio = min(1.0, max(0.0, (p - 0.5) * 2.0))
                let rearTargetX: CGFloat = count > 2 ? -13 : 15
                let rearTargetY: CGFloat = count > 2 ? 14 : 8
                let rearTargetAngle: Double = count > 2 ? -3.8 : 3.8
                let targetShrink: CGFloat = count > 2 ? 0.09 : 0.05

                let x = (-swingOut * 138.0) + (tuckRatio * rearTargetX)
                let y = (p * 6.0) + (tuckRatio * (rearTargetY - 6.0))
                let scale = 1.0 - (targetShrink * p)
                let angle = Double(-swingOut * 7.5) + (tuckRatio * rearTargetAngle)
                // For 2-card stacks, keep t == -1 at the exact same rest transform/opacity as t == +1
                // so reversing from card 2 back to card 1 across integer boundaries never pops/vanishes.
                let zIndex: Double = p < 0.48 ? 100.0 : (count == 2 ? 68.0 : 40.0)
                let opacity = count == 2
                    ? (1.0 - Double(tuckRatio) * 0.04)
                    : (1.0 - Double(tuckRatio) * 0.12)
                return CardGeometry(x: x, y: y, scale: scale, angle: angle, opacity: opacity, zIndex: zIndex)
            } else {
                let fade = max(0.0, 1.0 - Double((-t - 1.0) / 0.45))
                return CardGeometry(
                    x: -13.0,
                    y: 14.0,
                    scale: 0.91,
                    angle: -3.8,
                    opacity: count > 2 ? 0.88 * fade : 0.0,
                    zIndex: 20.0
                )
            }
        } else if t <= 1.0 {
            let p = t
            let x = p * 15.0
            let y = p * 8.0
            let scale = 1.0 - p * 0.05
            let angle = Double(p) * 3.8
            let opacity = 1.0 - Double(p) * 0.04
            let zIndex = 88.0 - Double(p) * 18.0
            return CardGeometry(x: x, y: y, scale: scale, angle: angle, opacity: opacity, zIndex: zIndex)
        } else if t <= 2.0 {
            let p = min(1.0, t - 1.0)
            let x = 15.0 * (1.0 - p * 0.65)
            let y = 8.0 + p * 6.0
            let scale = 0.95 - p * 0.06
            let angle = 3.8 * (1.0 - Double(p))
            let opacity = count > 2 ? max(0.0, 0.96 * Double(max(0.0, 1.0 - (p / 0.85)))) : 0.0
            let zIndex = 58.0 - Double(p) * 28.0
            return CardGeometry(x: x, y: y, scale: scale, angle: angle, opacity: opacity, zIndex: zIndex)
        } else {
            return CardGeometry(x: 5.25, y: 14.0, scale: 0.89, angle: 0.0, opacity: 0.0, zIndex: 10.0)
        }
    }
}

private struct MediaShareFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

public struct AnimatedGIFView: UIViewRepresentable {
    public let data: Data
    public var contentMode: UIView.ContentMode = .scaleAspectFit

    public init(data: Data, contentMode: UIView.ContentMode = .scaleAspectFit) {
        self.data = data
        self.contentMode = contentMode
    }

    public func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        return imageView
    }

    public func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.contentMode = contentMode
        guard context.coordinator.lastDataHash != data.hashValue else { return }
        context.coordinator.lastDataHash = data.hashValue
        uiView.image = Self.decodeAnimatedGIF(from: data) ?? UIImage(data: data)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
        uiView.image = nil
        coordinator.lastDataHash = 0
    }

    @MainActor
    public final class Coordinator {
        var lastDataHash: Int = 0
    }

    private static func decodeAnimatedGIF(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }

        let strideStep = max(1, count / 90)
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 900
        ]

        var frames: [UIImage] = []
        var totalDuration: TimeInterval = 0
        var index = 0
        while index < count {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, thumbOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, index, nil) else {
                index += strideStep
                continue
            }
            var frameDuration: TimeInterval = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
               let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
                    frameDuration = unclamped
                } else if let delay = gifProps[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
                    frameDuration = delay
                }
            }
            if frameDuration < 0.02 { frameDuration = 0.08 }
            totalDuration += frameDuration * Double(strideStep)
            frames.append(UIImage(cgImage: cgImage))
            index += strideStep
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: max(0.1, totalDuration))
    }
}

@MainActor
@Observable
final class ContextMenuPreviewBridge {
    var isDismissing: Bool = false
}

public struct MediaContextMenuPreview: View {
    public let item: FeedMedia
    public let disableHDR: Bool
    public var cornerRadius: CGFloat? = nil
    public var initialImage: UIImage? = nil
    public var hasBackingImageView: Bool = false
    var bridge: ContextMenuPreviewBridge? = nil
    public var onImageUpgraded: ((UIImage) -> Void)? = nil

    @State private var displayResult: LoadedImageResult?
    @State private var lockedPreviewSize: CGSize
    @State private var isUpgradeSettled: Bool = false
    @State private var liveVideoURL: URL?
    @State private var showLiveVideo = false
    @State private var videoReady = false
    @State private var playTrigger = 0
    @State private var gifData: Data?

    public init(
        item: FeedMedia,
        disableHDR: Bool,
        cornerRadius: CGFloat? = nil,
        initialImage: UIImage? = nil,
        hasBackingImageView: Bool = false,
        onImageUpgraded: ((UIImage) -> Void)? = nil
    ) {
        self.init(
            item: item,
            disableHDR: disableHDR,
            cornerRadius: cornerRadius,
            initialImage: initialImage,
            hasBackingImageView: hasBackingImageView,
            bridge: nil,
            onImageUpgraded: onImageUpgraded
        )
    }

    init(
        item: FeedMedia,
        disableHDR: Bool,
        cornerRadius: CGFloat? = nil,
        initialImage: UIImage? = nil,
        hasBackingImageView: Bool = false,
        bridge: ContextMenuPreviewBridge? = nil,
        onImageUpgraded: ((UIImage) -> Void)? = nil
    ) {
        self.item = item
        self.disableHDR = disableHDR
        self.cornerRadius = cornerRadius
        self.initialImage = initialImage
        self.hasBackingImageView = hasBackingImageView
        self.bridge = bridge
        self.onImageUpgraded = onImageUpgraded

        let cached = ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1600, preferHDR: !disableHDR)
            ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: nil, preferHDR: !disableHDR)
            ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1200, preferHDR: !disableHDR)
            ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1080, preferHDR: false)
            ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 960, preferHDR: false)
            ?? ImagePipeline.cachedImageSync(urlString: item.thumbnailUrl, maxPixelSize: 1080, preferHDR: false)
            ?? ImagePipeline.cachedImageSync(urlString: item.thumbnailUrl, maxPixelSize: 960, preferHDR: false)
            ?? ImagePipeline.cachedAnyImageSync(urlString: item.sourceUrl)
            ?? ImagePipeline.cachedAnyImageSync(urlString: item.thumbnailUrl)
        let resolvedInitial: LoadedImageResult? = cached ?? initialImage.map {
            LoadedImageResult(
                image: $0,
                hasHDRGainMap: $0.isHighDynamicRange || ImagePipeline.cachedHDRFlagSync(urlString: item.sourceUrl),
                pixelSize: $0.size
            )
        }
        self._displayResult = State(initialValue: resolvedInitial)
        self._lockedPreviewSize = State(
            initialValue: Self.preferredSize(for: item, imageSize: resolvedInitial?.image.size ?? initialImage?.size)
        )
    }

    public static func preferredSize(for item: FeedMedia, imageSize: CGSize? = nil) -> CGSize {
        let inferredRatio = MediaGridView.inferredAspectRatio(from: item.sourceUrl)
            ?? MediaGridView.inferredAspectRatio(from: item.thumbnailUrl)
            ?? 1.25
        let actualRatio: CGFloat = {
            if let imageSize, imageSize.height > 0 {
                return imageSize.width / imageSize.height
            }
            return inferredRatio
        }()
        let clampedRatio = max(0.38, min(actualRatio, 2.6))
        let maxW: CGFloat = 340
        let maxH: CGFloat = 460
        if clampedRatio >= (maxW / maxH) {
            let w = maxW
            let h = max(110, w / clampedRatio)
            return CGSize(width: w, height: h)
        } else {
            let h = maxH
            let w = max(150, h * clampedRatio)
            return CGSize(width: w, height: h)
        }
    }

    public var body: some View {
        let width = lockedPreviewSize.width
        let height = lockedPreviewSize.height
        let isHDR = item.isHdr || (displayResult?.hasHDRGainMap ?? false)
        let showHDR = !disableHDR && isHDR
        let isLive = (liveVideoURL != nil) || item.isLivePhoto || ImagePipeline.cachedLiveFlagSync(urlString: item.sourceUrl)
        let isDismissing = bridge?.isDismissing ?? false

        GeometryReader { proxy in
            let liveWidth = proxy.size.width > 1 ? proxy.size.width : width
            let liveHeight = proxy.size.height > 1 ? proxy.size.height : height

            ZStack(alignment: .topTrailing) {
                ZStack {
                    if hasBackingImageView {
                        Color.clear
                    } else {
                        Color(.secondarySystemGroupedBackground)
                    }

                    if let gifData, item.isGif, !isDismissing {
                        AnimatedGIFView(data: gifData, contentMode: .scaleAspectFill)
                            .frame(width: liveWidth, height: liveHeight)
                            .clipped()
                    } else if let displayResult {
                        if !hasBackingImageView || (!isDismissing && isUpgradeSettled && showHDR) {
                            Image(uiImage: displayResult.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: liveWidth, height: liveHeight)
                                .clipped()
                                .allowedDynamicRange((!isDismissing && showHDR) ? .high : .standard)
                        }

                        if !isDismissing, let liveVideoURL, showLiveVideo {
                            LiveVideoPlayerView(
                                videoURL: liveVideoURL,
                                playTrigger: playTrigger,
                                isLooping: false,
                                isMuted: true,
                                videoGravity: .resizeAspectFill,
                                onReadyToDisplay: {
                                    withAnimation(.easeIn(duration: 0.16)) {
                                        videoReady = true
                                    }
                                },
                                onPlaybackEnded: {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        videoReady = false
                                        showLiveVideo = false
                                    }
                                }
                            )
                            .frame(width: liveWidth, height: liveHeight)
                            .clipped()
                            .opacity(videoReady ? 1 : 0)
                            .allowsHitTesting(false)
                        }
                    } else if !hasBackingImageView {
                        ProgressView()
                    }
                }
                .frame(width: liveWidth, height: liveHeight)

                if isLive || isHDR {
                    HStack(spacing: 8) {
                        if isLive {
                            HStack(spacing: 2) {
                                Image(systemName: "livephoto")
                                Text("Live")
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                        }
                        if isHDR {
                            Text("HDR")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .glassEffect(.regular, in: .capsule)
                        }
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: liveWidth, height: liveHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? 0, style: .continuous))
        }
        .frame(
            idealWidth: width,
            maxWidth: hasBackingImageView ? .infinity : width,
            idealHeight: height,
            maxHeight: hasBackingImageView ? .infinity : height
        )
        .frame(width: hasBackingImageView ? nil : width, height: hasBackingImageView ? nil : height)
        .ignoresSafeArea()
        .task(id: item.id) {
            showLiveVideo = false
            videoReady = false
            liveVideoURL = nil
            isUpgradeSettled = false

            let hadInitialImage = (displayResult != nil || initialImage != nil)
            if hadInitialImage {
                // Allow the context menu lift & spring expansion (~260ms) to finish
                // before swapping image textures or activating EDR/HDR dynamic range.
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
            }

            if let loaded = await ImagePipeline.shared.loadImage(
                urlString: item.sourceUrl,
                maxPixelSize: 1600,
                preferHDR: !disableHDR
            ) {
                guard !Task.isCancelled else { return }
                if !hadInitialImage {
                    lockedPreviewSize = Self.preferredSize(for: item, imageSize: loaded.image.size)
                }
                onImageUpgraded?(loaded.image)
                displayResult = loaded
            }
            guard !Task.isCancelled else { return }
            isUpgradeSettled = true

            if item.isGif {
                gifData = await ImagePipeline.shared.fetchRawData(urlString: item.sourceUrl)
                return
            }

            guard let vidFile = await ImagePipeline.shared.resolveLiveVideoFile(for: item),
                  !Task.isCancelled else {
                return
            }
            liveVideoURL = vidFile

            let activeHDR = !disableHDR && (item.isHdr || (displayResult?.hasHDRGainMap ?? false))
            let delayNs: UInt64 = activeHDR ? 720_000_000 : 120_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled, !(bridge?.isDismissing ?? false) else { return }

            videoReady = false
            showLiveVideo = true
            playTrigger += 1
        }
    }
}

private struct MediaShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DeckContextPreviewConfig {
    let activeItem: FeedMedia
    let cornerRadius: CGFloat
    let adaptiveContentMode: Bool
    let shouldLetterboxWide: Bool
    let disableHDR: Bool
    let appState: AppState
    let onPreviewLiftedChanged: (Bool) -> Void
    let onShareFile: ((URL) -> Void)?
}

struct HorizontalDeckPanOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let activeCardSize: CGSize
    let previewConfig: DeckContextPreviewConfig?
    let onTap: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat, Bool) -> Void

    init(
        isEnabled: Bool,
        activeCardSize: CGSize,
        previewConfig: DeckContextPreviewConfig? = nil,
        onTap: @escaping () -> Void,
        onDragChanged: @escaping (CGFloat) -> Void,
        onDragEnded: @escaping (CGFloat, CGFloat, Bool) -> Void
    ) {
        self.isEnabled = isEnabled
        self.activeCardSize = activeCardSize
        self.previewConfig = previewConfig
        self.onTap = onTap
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            activeCardSize: activeCardSize,
            previewConfig: previewConfig,
            onTap: onTap,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )
    }

    func makeUIView(context: Context) -> OverlayView {
        let view = OverlayView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = false
        view.activeCardSize = activeCardSize
        view.cardBackingView.frame = CGRect(origin: .zero, size: activeCardSize)
        view.cardBackingView.layer.cornerRadius = previewConfig?.cornerRadius ?? 18

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: pan)

        context.coordinator.panRecognizer = pan
        context.coordinator.overlayView = view
        view.onTouchDown = { [weak coordinator = context.coordinator] in
            coordinator?.handleTouchDown()
        }
        view.onTouchFinished = { [weak coordinator = context.coordinator] in
            coordinator?.handleTouchFinished()
        }
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        if previewConfig != nil {
            let contextMenu = UIContextMenuInteraction(delegate: context.coordinator)
            view.addInteraction(contextMenu)
        }
        return view
    }

    func updateUIView(_ uiView: OverlayView, context: Context) {
        uiView.activeCardSize = activeCardSize
        uiView.isUserInteractionEnabled = isEnabled
        uiView.onTouchDown = { [weak coordinator = context.coordinator] in
            coordinator?.handleTouchDown()
        }
        uiView.onTouchFinished = { [weak coordinator = context.coordinator] in
            coordinator?.handleTouchFinished()
        }
        if !context.coordinator.isPreviewMenuActive {
            uiView.configureBackingGeometry(
                size: activeCardSize,
                cornerRadius: previewConfig?.cornerRadius ?? 18
            )
        }

        context.coordinator.isEnabled = isEnabled
        context.coordinator.activeCardSize = activeCardSize
        context.coordinator.previewConfig = previewConfig
        context.coordinator.onTap = onTap
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
        context.coordinator.overlayView = uiView
    }

    static func dismantleUIView(_ uiView: OverlayView, coordinator: Coordinator) {
        uiView.isUserInteractionEnabled = false
        uiView.cardBackingView.isHidden = true
        coordinator.isEnabled = false
        coordinator.isPreviewMenuActive = false
        coordinator.previewConfig?.onPreviewLiftedChanged(false)
    }

    final class OverlayView: UIView {
        var activeCardSize: CGSize = .zero
        var onTouchDown: (() -> Void)?
        var onTouchFinished: (() -> Void)?
        let cardBackingView = CardBackingSurfaceView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            cardBackingView.isUserInteractionEnabled = false
            cardBackingView.isHidden = true
            addSubview(cardBackingView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func configureBackingGeometry(size: CGSize, cornerRadius: CGFloat) {
            let targetBounds = bounds.size.width > 1 && bounds.size.height > 1
                ? bounds
                : CGRect(origin: .zero, size: size)
            cardBackingView.frame = targetBounds
            cardBackingView.applyCornerRadius(cornerRadius)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            onTouchDown?()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            onTouchFinished?()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            onTouchFinished?()
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard isUserInteractionEnabled, bounds.contains(point) else { return nil }
            let cardMaxX = min(bounds.maxX, (bounds.width + activeCardSize.width) * 0.5)
            let cardMaxY = min(bounds.maxY, (bounds.height + activeCardSize.height) * 0.5)
            let buttonExclusion = CGRect(
                x: cardMaxX - 96,
                y: cardMaxY - 48,
                width: 96,
                height: 48
            )
            if buttonExclusion.contains(point) {
                return nil
            }
            return self
        }
    }

    final class CardBackingSurfaceView: UIView {
        private let backdropImageView: UIImageView = {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.alpha = 0.70
            iv.isHidden = true
            return iv
        }()

        private let blurOverlayView: UIVisualEffectView = {
            let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            view.alpha = 0.85
            view.isHidden = true
            return view
        }()

        private let mainImageView: UIImageView = {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            return iv
        }()

        var allowsVisibility: Bool = false {
            didSet {
                super.isHidden = !allowsVisibility
            }
        }

        override var isHidden: Bool {
            get { super.isHidden }
            set {
                // Prevent UIKit's _UIContextMenuPresentation dismissal completion from un-hiding
                // cardBackingView after the preview closes or while the user is swiping to the next card.
                super.isHidden = allowsVisibility ? newValue : true
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            clipsToBounds = true
            layer.cornerCurve = .continuous
            addSubview(backdropImageView)
            addSubview(blurOverlayView)
            addSubview(mainImageView)
            super.isHidden = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            backdropImageView.frame = bounds
            blurOverlayView.frame = bounds
            mainImageView.frame = bounds
        }

        func applyCornerRadius(_ cornerRadius: CGFloat) {
            layer.cornerRadius = cornerRadius
            layer.cornerCurve = .continuous
            mainImageView.layer.cornerRadius = cornerRadius
            mainImageView.layer.cornerCurve = .continuous
        }

        func configure(image: UIImage?, letterbox: Bool, cornerRadius: CGFloat) {
            applyCornerRadius(cornerRadius)
            mainImageView.image = image
            mainImageView.contentMode = letterbox ? .scaleAspectFit : .scaleAspectFill
            backdropImageView.image = letterbox ? image : nil
            backdropImageView.isHidden = !letterbox
            blurOverlayView.isHidden = !letterbox
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    @MainActor
    final class MediaContextMenuPreviewController: UIViewController {
        private let item: FeedMedia
        private let initialImage: UIImage?
        private let disableHDR: Bool
        private let cornerRadius: CGFloat
        private let appState: AppState
        private let targetSize: CGSize
        private let containerView = UIView()
        private let immediateImageView = UIImageView()
        private let bridge = ContextMenuPreviewBridge()

        init(
            item: FeedMedia,
            initialImage: UIImage?,
            disableHDR: Bool,
            cornerRadius: CGFloat,
            appState: AppState,
            targetSize: CGSize
        ) {
            self.item = item
            self.initialImage = initialImage
            self.disableHDR = disableHDR
            self.cornerRadius = cornerRadius
            self.appState = appState
            self.targetSize = targetSize
            super.init(nibName: nil, bundle: nil)
            self.preferredContentSize = targetSize
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func loadView() {
            let root = UIView(frame: CGRect(origin: .zero, size: targetSize))
            root.backgroundColor = .clear
            root.clipsToBounds = true
            root.layer.cornerRadius = cornerRadius
            root.layer.cornerCurve = .continuous
            self.view = root
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            containerView.frame = view.bounds
            containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            containerView.backgroundColor = .secondarySystemGroupedBackground
            containerView.clipsToBounds = true
            containerView.layer.cornerRadius = cornerRadius
            containerView.layer.cornerCurve = .continuous
            view.addSubview(containerView)

            immediateImageView.frame = containerView.bounds
            immediateImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            immediateImageView.contentMode = .scaleAspectFill
            immediateImageView.clipsToBounds = true
            immediateImageView.layer.cornerRadius = cornerRadius
            immediateImageView.layer.cornerCurve = .continuous
            immediateImageView.image = initialImage
            containerView.addSubview(immediateImageView)

            let host = UIHostingController(
                rootView: MediaContextMenuPreview(
                    item: item,
                    disableHDR: disableHDR,
                    cornerRadius: cornerRadius,
                    initialImage: initialImage,
                    hasBackingImageView: initialImage != nil,
                    bridge: bridge,
                    onImageUpgraded: { [weak self] upgradedImage in
                        self?.immediateImageView.image = upgradedImage
                    }
                )
                .environment(appState)
            )
            addChild(host)
            host.view.backgroundColor = .clear
            host.view.isOpaque = false
            host.view.frame = containerView.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.clipsToBounds = true
            host.view.layer.cornerRadius = cornerRadius
            host.view.layer.cornerCurve = .continuous
            containerView.addSubview(host.view)
            host.didMove(toParent: self)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.cornerRadius = cornerRadius
            view.layer.cornerCurve = .continuous
            containerView.layer.cornerRadius = cornerRadius
            containerView.layer.cornerCurve = .continuous
            immediateImageView.layer.cornerRadius = cornerRadius
            immediateImageView.layer.cornerCurve = .continuous
        }

        func prepareForDismissal() {
            bridge.isDismissing = true
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        var isEnabled: Bool
        var activeCardSize: CGSize
        var previewConfig: DeckContextPreviewConfig?
        var onTap: () -> Void
        var onDragChanged: (CGFloat) -> Void
        var onDragEnded: (CGFloat, CGFloat, Bool) -> Void
        var isPreviewMenuActive = false
        weak var panRecognizer: UIPanGestureRecognizer?
        weak var overlayView: OverlayView?
        weak var activePreviewController: MediaContextMenuPreviewController?

        init(
            isEnabled: Bool,
            activeCardSize: CGSize,
            previewConfig: DeckContextPreviewConfig?,
            onTap: @escaping () -> Void,
            onDragChanged: @escaping (CGFloat) -> Void,
            onDragEnded: @escaping (CGFloat, CGFloat, Bool) -> Void
        ) {
            self.isEnabled = isEnabled
            self.activeCardSize = activeCardSize
            self.previewConfig = previewConfig
            self.onTap = onTap
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
        }

        func handleTouchDown() {
            // Pre-configure backing image and geometry quietly without unhiding cardBackingView
            // so starting a horizontal swipe right after dismissing a preview never shows cardBackingView.
            guard isEnabled, !isPreviewMenuActive, let cfg = previewConfig, let overlay = overlayView else { return }
            let targetSize = overlay.bounds.size.width > 1 && overlay.bounds.size.height > 1
                ? overlay.bounds.size
                : activeCardSize
            overlay.configureBackingGeometry(size: targetSize, cornerRadius: cfg.cornerRadius)
            let img = cachedDisplayImage(
                for: cfg.activeItem,
                adaptiveContentMode: cfg.adaptiveContentMode,
                disableHDR: cfg.disableHDR
            )
            overlay.cardBackingView.configure(
                image: img,
                letterbox: cfg.shouldLetterboxWide,
                cornerRadius: cfg.cornerRadius
            )
        }

        func handleTouchFinished() {
            guard !isPreviewMenuActive else { return }
            overlayView?.cardBackingView.allowsVisibility = false
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            if !isPreviewMenuActive {
                overlayView?.cardBackingView.allowsVisibility = false
            }
            onTap()
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let dx = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .began:
                isPreviewMenuActive = false
                overlayView?.cardBackingView.allowsVisibility = false
                previewConfig?.onPreviewLiftedChanged(false)
                onDragChanged(dx)
            case .changed:
                onDragChanged(dx)
            case .ended:
                let vx = recognizer.velocity(in: recognizer.view).x
                let predicted = dx + vx * 0.18
                onDragEnded(dx, predicted, false)
            case .cancelled, .failed:
                onDragEnded(dx, dx, true)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === panRecognizer,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }
            guard isEnabled else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.15 && abs(velocity.x) > 12
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard isEnabled, gestureRecognizer === panRecognizer else { return false }
            return otherGestureRecognizer is UIPanGestureRecognizer
                && !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer)
        }

        private func cachedDisplayImage(
            for item: FeedMedia,
            adaptiveContentMode: Bool,
            disableHDR: Bool
        ) -> UIImage? {
            let primaryURL = adaptiveContentMode ? item.sourceUrl : item.thumbnailUrl
            let primaryMax: CGFloat = adaptiveContentMode ? 960 : 1080
            let loaded = ImagePipeline.cachedImageSync(urlString: primaryURL, maxPixelSize: primaryMax, preferHDR: false)
                ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1600, preferHDR: !disableHDR)
                ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: nil, preferHDR: !disableHDR)
                ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1200, preferHDR: !disableHDR)
                ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1080, preferHDR: false)
                ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 960, preferHDR: false)
                ?? ImagePipeline.cachedImageSync(urlString: item.thumbnailUrl, maxPixelSize: 1080, preferHDR: false)
                ?? ImagePipeline.cachedImageSync(urlString: item.thumbnailUrl, maxPixelSize: 960, preferHDR: false)
                ?? ImagePipeline.cachedAnyImageSync(urlString: primaryURL)
                ?? ImagePipeline.cachedAnyImageSync(urlString: item.sourceUrl)
                ?? ImagePipeline.cachedAnyImageSync(urlString: item.thumbnailUrl)
            return loaded?.image
        }

        private func prepareCardBackingView(cfg: DeckContextPreviewConfig) -> OverlayView? {
            guard let overlay = overlayView else { return nil }
            let targetSize = overlay.bounds.size.width > 1 && overlay.bounds.size.height > 1
                ? overlay.bounds.size
                : activeCardSize
            overlay.configureBackingGeometry(size: targetSize, cornerRadius: cfg.cornerRadius)
            let img = cachedDisplayImage(
                for: cfg.activeItem,
                adaptiveContentMode: cfg.adaptiveContentMode,
                disableHDR: cfg.disableHDR
            )
            overlay.cardBackingView.configure(
                image: img,
                letterbox: cfg.shouldLetterboxWide,
                cornerRadius: cfg.cornerRadius
            )
            overlay.cardBackingView.allowsVisibility = (img != nil)
            return overlay
        }

        private func targetedCardPreview(for overlay: OverlayView, cornerRadius: CGFloat) -> UITargetedPreview {
            overlay.cardBackingView.applyCornerRadius(cornerRadius)
            let params = UIPreviewParameters()
            params.backgroundColor = .clear
            // Use UIBezierPath(roundedRect:cornerRadius:) rather than UIBezierPath(cgPath:)
            // so UIKit preserves its internal _isRoundedRect/_cornerRadius metadata on the platter
            // and never snaps the preview corners to 90-degree right angles during lift/morph.
            let roundedPath = UIBezierPath(
                roundedRect: overlay.cardBackingView.bounds,
                cornerRadius: cornerRadius
            )
            params.visiblePath = roundedPath
            params.shadowPath = roundedPath
            return UITargetedPreview(view: overlay.cardBackingView, parameters: params)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard isEnabled, let cfg = previewConfig else { return nil }
            let item = cfg.activeItem
            let cachedImg = cachedDisplayImage(
                for: item,
                adaptiveContentMode: cfg.adaptiveContentMode,
                disableHDR: cfg.disableHDR
            )
            let previewSize = MediaContextMenuPreview.preferredSize(for: item, imageSize: cachedImg?.size)
            let disableHDR = cfg.disableHDR
            let cornerRadius = cfg.cornerRadius
            let appState = cfg.appState
            let hasShareHandler = (cfg.onShareFile != nil)

            _ = prepareCardBackingView(cfg: cfg)

            return UIContextMenuConfiguration(identifier: nil) { [weak self] in
                let controller = MediaContextMenuPreviewController(
                    item: item,
                    initialImage: cachedImg,
                    disableHDR: disableHDR,
                    cornerRadius: cornerRadius,
                    appState: appState,
                    targetSize: previewSize
                )
                self?.activePreviewController = controller
                return controller
            } actionProvider: { [weak self] _ in
                var actions: [UIAction] = [
                    UIAction(
                        title: "查看大图",
                        image: UIImage(systemName: "arrow.up.left.and.arrow.down.right")
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.overlayView?.cardBackingView.allowsVisibility = false
                            self?.onTap()
                        }
                    },
                    UIAction(
                        title: "保存到相册",
                        image: UIImage(systemName: "square.and.arrow.down")
                    ) { _ in
                        Task { @MainActor in
                            await MediaActionsContextMenu.saveImageToPhotos(item, appState: appState)
                        }
                    },
                    UIAction(
                        title: "复制图片",
                        image: UIImage(systemName: "doc.on.doc")
                    ) { _ in
                        Task { @MainActor in
                            await MediaActionsContextMenu.copyImageToPasteboard(item, appState: appState)
                        }
                    },
                    UIAction(
                        title: "复制图片链接",
                        image: UIImage(systemName: "link")
                    ) { _ in
                        Task { @MainActor in
                            UIPasteboard.general.string = item.sourceUrl
                            appState.showToast("已复制图片链接")
                        }
                    }
                ]
                if hasShareHandler {
                    actions.append(
                        UIAction(
                            title: "分享图片",
                            image: UIImage(systemName: "square.and.arrow.up")
                        ) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, let share = self.previewConfig?.onShareFile else { return }
                                await MediaActionsContextMenu.shareImageFile(
                                    item,
                                    appState: appState,
                                    onShareFile: share
                                )
                            }
                        }
                    )
                }
                return UIMenu(title: "", children: actions)
            }
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            guard let cfg = previewConfig,
                  let overlay = prepareCardBackingView(cfg: cfg) else { return nil }
            isPreviewMenuActive = true
            return targetedCardPreview(for: overlay, cornerRadius: cfg.cornerRadius)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            guard let overlay = overlayView, let cfg = previewConfig else { return nil }
            return targetedCardPreview(for: overlay, cornerRadius: cfg.cornerRadius)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willDisplayMenuFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            // Once the preview platter has lifted, keep cardBackingView hidden so the live SwiftUI
            // OrbitalDeckStage underneath is always unobstructed.
            animator?.addCompletion { [weak self] in
                MainActor.assumeIsolated {
                    self?.overlayView?.cardBackingView.allowsVisibility = false
                }
            }
        }

        private func completePreviewDismissal() {
            previewConfig?.onPreviewLiftedChanged(false)
            overlayView?.cardBackingView.allowsVisibility = false
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            isPreviewMenuActive = false
            overlayView?.cardBackingView.allowsVisibility = false
            activePreviewController?.prepareForDismissal()
            if let animator {
                animator.addCompletion { [weak self] in
                    MainActor.assumeIsolated {
                        self?.completePreviewDismissal()
                    }
                }
            } else {
                completePreviewDismissal()
            }
        }
    }
}