import CoolapkKit
import Photos
import SwiftUI
import UIKit

public struct MediaGridView: View {
    public let items: [FeedMedia]
    public var onTapItem: ((Int) -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
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
                    Button {
                        triggerTap(at: index)
                    } label: {
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
                            .applyZoomSource(id: sourceID, in: zoomNamespace)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        mediaContextMenu(item: item, index: index)
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
        if let onTapItem {
            onTapItem(index)
        } else {
            appState.openMedia(items, at: index, sourcePrefix: "media-\(transitionSeed)")
        }
    }

    private func singleImage(_ item: FeedMedia, index: Int) -> some View {
        let ratio = Self.inferredAspectRatio(from: item.thumbnailUrl) ?? 1.45
        let clampedRatio = max(0.45, min(ratio, 2.2))
        let maxW: CGFloat = 310
        let targetWidth: CGFloat = clampedRatio >= 1.0 ? maxW : min(maxW, max(165, 240 * clampedRatio))
        let targetHeight: CGFloat = min(300, max(120, targetWidth / clampedRatio))
        let sourceID = onTapItem == nil ? "media-\(transitionSeed)-\(index)" : nil

        return Button {
            triggerTap(at: index)
        } label: {
            ZStack(alignment: .topTrailing) {
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
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .applyZoomSource(id: sourceID, in: zoomNamespace)

                badgeStack(for: item, isLong: (ratio < 0.42))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            mediaContextMenu(item: item, index: index)
        }
    }

    @ViewBuilder
    private func mediaContextMenu(item: FeedMedia, index: Int) -> some View {
        Button {
            triggerTap(at: index)
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
                    shareFileURL = temp
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

    @ViewBuilder
    private func badgeStack(for item: FeedMedia, isLong: Bool = false) -> some View {
        let showLive = item.isLivePhoto
        let showHDR = item.isHdr && !appState.settings.disableHDR
        let showGIF = item.isGif

        if showLive || showHDR || showGIF || isLong {
            HStack(spacing: 4) {
                if showLive { badgePill("LIVE") }
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

    private static func inferredAspectRatio(from urlString: String) -> CGFloat? {
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

private struct PhotoStackCardView<MenuContent: View>: View {
    let items: [FeedMedia]
    @Binding var deckPhase: CGFloat
    let transitionSeed: String
    let enableZoomSource: Bool
    let disableHDR: Bool
    let onTapCard: (Int) -> Void
    @ViewBuilder let contextMenuBuilder: (FeedMedia, Int) -> MenuContent

    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var dragProgress: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var lastDragEndedAt: Date = .distantPast

    private var currentNearestIndex: Int {
        let count = items.count
        guard count > 0 else { return 0 }
        let rounded = Int((deckPhase + dragProgress).rounded())
        return ((rounded % count) + count) % count
    }

    var body: some View {
        let count = items.count
        let visibleLayers = min(count, 3)
        let activeIdx = currentNearestIndex
        let activeItem = items[activeIdx]

        ZStack {
            OrbitalDeckStage(
                phase: deckPhase + dragProgress,
                count: count,
                cardHeight: 218
            ) { itemIndex, isFront in
                let item = items[itemIndex]
                let sourceID = (isFront && enableZoomSource) ? "media-\(transitionSeed)-\(itemIndex)" : nil

                Color.clear
                    .frame(height: 218)
                    .overlay {
                        RemoteImageView(
                            url: item.thumbnailUrl,
                            maxPixelSize: 1080
                        )
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.4)
                    }
                    .applyZoomSource(id: sourceID, in: zoomNamespace)
                    .onTapGesture {
                        guard isFront,
                              !isHorizontalDragging,
                              abs(dragProgress) < 0.04,
                              Date().timeIntervalSince(lastDragEndedAt) > 0.30 else { return }
                        onTapCard(itemIndex)
                    }
                    .contextMenu {
                        contextMenuBuilder(item, itemIndex)
                    }
            }
            .padding(.leading, visibleLayers > 2 ? 16 : 0)
            .padding(.trailing, visibleLayers > 1 ? 20 : 0)
            .padding(.bottom, visibleLayers > 1 ? 16 : 0)

            // Stationary floating controls outside moving/rotating deck so badges never deform.
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        if activeItem.isLivePhoto { stackPill("LIVE") }
                        if activeItem.isHdr && !disableHDR { stackPill("HDR") }
                        if activeItem.isGif { stackPill("GIF") }
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
            .padding(.top, 10)
            .padding(.bottom, (visibleLayers > 1 ? 16 : 0) + 10)
            .padding(.leading, visibleLayers > 2 ? 26 : 10)
            .padding(.trailing, (visibleLayers > 1 ? 20 : 0) + 10)
        }
        .frame(height: visibleLayers > 1 ? 236 : 218)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard count > 1 else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if isHorizontalDragging || abs(dx) > max(12, abs(dy) * 1.15) {
                        isHorizontalDragging = true
                        dragProgress = max(-1.15, min(1.15, -dx / 210.0))
                    }
                }
                .onEnded { value in
                    guard count > 1 else { return }
                    let dx = value.translation.width
                    let predicted = value.predictedEndTranslation.width
                    let wasDragging = isHorizontalDragging || abs(dx) > 10
                    if wasDragging {
                        lastDragEndedAt = Date()
                    }
                    isHorizontalDragging = false
                    guard wasDragging else {
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
        let slotOffsets = Array((-1...maxBack).reversed())
        let activeRounded = Int(phase.rounded())

        ZStack {
            ForEach(slotOffsets, id: \.self) { stepOffset in
                let rawSlot = baseSlot + stepOffset
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
        // t == 0: center front card
        // t in [-0.5, 0]: active card swinging out left & dropping down a layer past -0.48
        // t in [-1.0, -0.5]: tucking under behind into back-left deck slot
        // t in [0, 1]: next card moving from back-right slot into center front
        // t in [1, 2]: deeper back layer peaking from opposite edge
        if t < 0 {
            let clamped = max(-1.0, t)
            let swingOut = sin(-clamped * .pi)
            let tuckRatio = min(1.0, max(0.0, (-clamped - 0.5) * 2.0))
            let rearTargetX: CGFloat = count > 2 ? -13 : 15
            let rearTargetY: CGFloat = count > 2 ? 15 : 8
            let rearTargetAngle: Double = count > 2 ? -3.8 : 3.8
            let targetShrink: CGFloat = count > 2 ? 0.09 : 0.05

            let x = (-swingOut * 138.0) + (tuckRatio * rearTargetX)
            let y = (abs(clamped) * 6.0) + (tuckRatio * (rearTargetY - 6.0))
            let scale = 1.0 - (targetShrink * min(1.0, abs(clamped)))
            let angle = Double(-swingOut * 7.5) + (tuckRatio * rearTargetAngle)
            let zIndex: Double = clamped > -0.48 ? 100.0 : 12.0
            let fadeAtRest = (count == 2 && clamped < -0.94) ? 0.0 : 1.0
            let opacity = (1.0 - Double(tuckRatio) * 0.10) * fadeAtRest
            return CardGeometry(x: x, y: y, scale: scale, angle: angle, opacity: opacity, zIndex: zIndex)
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
            let p = min(1.35, t - 1.0)
            let x = 15.0 + p * (-28.0)
            let y = 8.0 + p * 7.0
            let scale = 0.95 - p * 0.04
            let angle = 3.8 + Double(p) * (-7.6)
            let opacity = max(0.0, 0.96 - Double(p) * 0.14 - (t > 2.0 ? Double(t - 2.0) * 1.4 : 0.0))
            let zIndex = 58.0 - Double(p) * 20.0
            return CardGeometry(x: x, y: y, scale: scale, angle: angle, opacity: opacity, zIndex: zIndex)
        }
    }
}

private struct MediaShareFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct MediaShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
