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
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 12)
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
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 14)
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
            Task { await saveImageToPhotos(item) }
        } label: {
            Label("保存到相册", systemImage: "square.and.arrow.down")
        }

        Button {
            Task { await copyImageToPasteboard(item) }
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
            Task {
                if let temp = await ImagePipeline.shared.downloadToTemporaryFile(
                    urlString: item.sourceUrl,
                    defaultExtension: item.isGif ? "gif" : "jpg"
                ) {
                    onShareFile(temp)
                } else {
                    appState.showToast("准备分享文件失败")
                }
            }
        } label: {
            Label("分享图片", systemImage: "square.and.arrow.up")
        }
    }

    private func saveImageToPhotos(_ item: FeedMedia) async {
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

    private func copyImageToPasteboard(_ item: FeedMedia) async {
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
    @ViewBuilder public let contextMenuBuilder: (FeedMedia, Int) -> MenuContent

    @Environment(\.zoomNamespace) private var zoomNamespace
    @Environment(\.replySwipeLock) private var replySwipeLock
    @Environment(\.replyCardCoordinateSpace) private var replyCardCoordinateSpace
    @State private var dragProgress: CGFloat = 0
    @State private var isHorizontalDragging = false
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
            OrbitalDeckStage(
                phase: deckPhase + dragProgress,
                count: count,
                cardHeight: maxCardHeight
            ) { itemIndex, isFront in
                let item = items[itemIndex]
                let sourceID = (isFront && enableZoomSource) ? "media-\(transitionSeed)-\(itemIndex)" : nil
                let ratio = ratioForItem(at: itemIndex)
                let itemSize = cardFrame(at: itemIndex, maxStageWidth: innerStageWidth)
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
                    .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: cornerRadius)
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .contextMenu {
                        contextMenuBuilder(item, itemIndex)
                    }
                    .onTapGesture {
                        guard isFront,
                              !isHorizontalDragging,
                              abs(dragProgress) < 0.04,
                              Date().timeIntervalSince(lastDragEndedAt) > 0.30 else { return }
                        onTapCard(itemIndex)
                    }
            }
            .padding(.leading, leftInset)
            .padding(.trailing, rightInset)
            .padding(.bottom, bottomInset)

            if count > 1 {
                HorizontalDeckPanOverlay(
                    isEnabled: count > 1,
                    activeCardSize: activeCardSize,
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
                .frame(height: maxCardHeight)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .contextMenu {
                    contextMenuBuilder(activeItem, activeIdx)
                }
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
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contextMenu {
            contextMenuBuilder(activeItem, activeIdx)
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
    @ViewBuilder public let cardBuilder: (Int, Bool) -> CardContent

    public var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    public init(
        phase: CGFloat,
        count: Int,
        cardHeight: CGFloat,
        @ViewBuilder cardBuilder: @escaping (Int, Bool) -> CardContent
    ) {
        self.phase = phase
        self.count = count
        self.cardHeight = cardHeight
        self.cardBuilder = cardBuilder
    }

    public var body: some View {
        let baseSlot = Int(floor(phase))
        let maxBack = min(2, max(0, count - 1))
        let rawSlots = count <= 1 ? [0] : Array((baseSlot - 1)...(baseSlot + maxBack))
        let activeRounded = Int(phase.rounded())

        ZStack {
            ForEach(rawSlots, id: \.self) { rawSlot in
                let itemIndex = ((rawSlot % count) + count) % count
                let t = CGFloat(rawSlot) - phase
                let isFront = (rawSlot == activeRounded) && abs(t) < 0.35
                let geometry = cardGeometry(for: t, count: count)

                cardBuilder(itemIndex, isFront)
                    .scaleEffect(geometry.scale)
                    .rotationEffect(.degrees(geometry.angle))
                    .offset(x: geometry.x, y: geometry.y)
                    .opacity(geometry.opacity)
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
        } else {
            let p = min(1.0, t - 1.0)
            let x = 15.0 * (1.0 - p * 0.65)
            let y = 8.0 + p * 6.0
            let scale = 0.95 - p * 0.06
            let angle = 3.8 * (1.0 - Double(p))
            let opacity = count > 2 ? max(0.0, 0.96 * Double(max(0.0, 1.0 - (p / 0.85)))) : 0.0
            let zIndex = 58.0 - Double(p) * 28.0
            return CardGeometry(x: x, y: y, scale: scale, angle: angle, opacity: opacity, zIndex: zIndex)
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

public struct MediaContextMenuPreview: View {
    public let item: FeedMedia
    public let disableHDR: Bool

    @State private var displayResult: LoadedImageResult?
    @State private var liveVideoURL: URL?
    @State private var showLiveVideo = false
    @State private var videoReady = false
    @State private var playTrigger = 0
    @State private var gifData: Data?

    public init(item: FeedMedia, disableHDR: Bool) {
        self.item = item
        self.disableHDR = disableHDR
        let initial = ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: nil, preferHDR: !disableHDR)
            ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1200, preferHDR: !disableHDR)
            ?? ImagePipeline.cachedImageSync(urlString: item.sourceUrl, maxPixelSize: 1080, preferHDR: false)
            ?? ImagePipeline.cachedImageSync(urlString: item.thumbnailUrl, maxPixelSize: 1080, preferHDR: false)
            ?? ImagePipeline.cachedImageSync(urlString: item.thumbnailUrl, maxPixelSize: 420, preferHDR: false)
            ?? ImagePipeline.cachedImageSync(urlString: item.thumbnailUrl, maxPixelSize: 320, preferHDR: false)
        self._displayResult = State(initialValue: initial)
    }

    public var body: some View {
        let inferredRatio = MediaGridView.inferredAspectRatio(from: item.sourceUrl)
            ?? MediaGridView.inferredAspectRatio(from: item.thumbnailUrl)
            ?? 1.25
        let actualRatio: CGFloat = {
            if let img = displayResult?.image, img.size.height > 0 {
                return img.size.width / img.size.height
            }
            return inferredRatio
        }()
        let clampedRatio = max(0.38, min(actualRatio, 2.6))
        let maxW: CGFloat = 340
        let maxH: CGFloat = 460
        let (width, height): (CGFloat, CGFloat) = {
            if clampedRatio >= (maxW / maxH) {
                let w = maxW
                let h = max(110, w / clampedRatio)
                return (w, h)
            } else {
                let h = maxH
                let w = max(150, h * clampedRatio)
                return (w, h)
            }
        }()
        let isHDR = item.isHdr || (displayResult?.hasHDRGainMap ?? false)
        let showHDR = !disableHDR && isHDR
        let isLive = (liveVideoURL != nil) || item.isLivePhoto || ImagePipeline.cachedLiveFlagSync(urlString: item.sourceUrl)

        ZStack(alignment: .topTrailing) {
            ZStack {
                if displayResult == nil && !(gifData != nil && item.isGif) {
                    Color(.secondarySystemGroupedBackground)
                } else {
                    Color.clear
                }

                if let gifData, item.isGif {
                    AnimatedGIFView(data: gifData, contentMode: .scaleAspectFill)
                } else if let displayResult {
                    let imageView = Image(uiImage: displayResult.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                    Group {
                        if showHDR {
                            imageView.allowedDynamicRange(.high)
                        } else {
                            imageView.allowedDynamicRange(.standard)
                        }
                    }

                    if let liveVideoURL, showLiveVideo {
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
                        .frame(width: width, height: height)
                        .clipped()
                        .opacity(videoReady ? 1 : 0)
                        .allowsHitTesting(false)
                    }
                } else {
                    ProgressView()
                }
            }

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
        .frame(width: width, height: height)
        .task(id: item.id) {
            showLiveVideo = false
            videoReady = false
            liveVideoURL = nil

            displayResult = await ImagePipeline.shared.loadImage(
                urlString: item.sourceUrl,
                maxPixelSize: nil,
                preferHDR: !disableHDR
            )
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
            let delayNs: UInt64 = activeHDR ? 1_000_000_000 : 350_000_000
            try? await Task.sleep(nanoseconds: delayNs)
            guard !Task.isCancelled else { return }

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

struct HorizontalDeckPanOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let activeCardSize: CGSize
    let onTap: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
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

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: pan)

        context.coordinator.panRecognizer = pan
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: OverlayView, context: Context) {
        uiView.activeCardSize = activeCardSize
        uiView.isUserInteractionEnabled = isEnabled
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onTap = onTap
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onDragEnded = onDragEnded
    }

    static func dismantleUIView(_ uiView: OverlayView, coordinator: Coordinator) {
        uiView.isUserInteractionEnabled = false
        coordinator.isEnabled = false
    }

    final class OverlayView: UIView {
        var activeCardSize: CGSize = .zero

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

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: Bool
        var onTap: () -> Void
        var onDragChanged: (CGFloat) -> Void
        var onDragEnded: (CGFloat, CGFloat, Bool) -> Void
        weak var panRecognizer: UIPanGestureRecognizer?

        init(
            isEnabled: Bool,
            onTap: @escaping () -> Void,
            onDragChanged: @escaping (CGFloat) -> Void,
            onDragEnded: @escaping (CGFloat, CGFloat, Bool) -> Void
        ) {
            self.isEnabled = isEnabled
            self.onTap = onTap
            self.onDragChanged = onDragChanged
            self.onDragEnded = onDragEnded
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTap()
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let dx = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .began, .changed:
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
    }
}
