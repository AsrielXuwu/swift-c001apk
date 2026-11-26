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
    @State private var activeStackIndex: Int = 0
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
                    activeIndex: $activeStackIndex,
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
    @Binding var activeIndex: Int
    let transitionSeed: String
    let enableZoomSource: Bool
    let disableHDR: Bool
    let onTapCard: (Int) -> Void
    @ViewBuilder let contextMenuBuilder: (FeedMedia, Int) -> MenuContent

    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var lastDragEndedAt: Date = .distantPast

    var body: some View {
        let count = items.count
        let visibleLayers = min(count, 3)

        ZStack {
            ForEach((0..<visibleLayers).reversed(), id: \.self) { depth in
                let itemIndex = (activeIndex + depth) % count
                let item = items[itemIndex]
                let isFront = (depth == 0)
                let sourceID = (isFront && enableZoomSource) ? "media-\(transitionSeed)-\(itemIndex)" : nil

                stackCard(item: item, index: itemIndex, isFront: isFront, count: count)
                    .applyZoomSource(id: sourceID, in: zoomNamespace)
                    .scaleEffect(scaleFor(depth: depth))
                    .rotationEffect(.degrees(rotationFor(depth: depth, isFront: isFront)))
                    .offset(x: xOffsetFor(depth: depth, isFront: isFront), y: yOffsetFor(depth: depth))
                    .opacity(depth == 2 ? 0.90 : (depth == 1 ? 0.96 : 1.0))
                    .zIndex(Double(visibleLayers - depth))
                    .allowsHitTesting(isFront)
            }
        }
        .padding(.leading, visibleLayers > 2 ? 16 : 0)
        .padding(.trailing, visibleLayers > 1 ? 20 : 0)
        .padding(.bottom, visibleLayers > 1 ? 18 : 0)
        .frame(height: 244)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if isHorizontalDragging || abs(dx) > max(12, abs(dy) * 1.15) {
                        isHorizontalDragging = true
                        dragOffset = dx
                    }
                }
                .onEnded { value in
                    let dx = value.translation.width
                    let predicted = value.predictedEndTranslation.width
                    let wasDragging = isHorizontalDragging || abs(dx) > 10
                    if wasDragging {
                        lastDragEndedAt = Date()
                    }
                    isHorizontalDragging = false
                    guard wasDragging else {
                        withAnimation(.snappy(duration: 0.22)) { dragOffset = 0 }
                        return
                    }
                    withAnimation(.snappy(duration: 0.28)) {
                        if dx < -42 || predicted < -90 {
                            activeIndex = (activeIndex + 1) % count
                        } else if dx > 42 || predicted > 90 {
                            activeIndex = (activeIndex - 1 + count) % count
                        }
                        dragOffset = 0
                    }
                }
        )
    }

    private func handleFrontCardTap(at index: Int) {
        guard !isHorizontalDragging,
              abs(dragOffset) < 4,
              Date().timeIntervalSince(lastDragEndedAt) > 0.30 else { return }
        onTapCard(index)
    }

    private func stackCard(item: FeedMedia, index: Int, isFront: Bool, count: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .frame(height: 218)
                .overlay {
                    RemoteImageView(
                        url: item.thumbnailUrl,
                        maxPixelSize: 1080
                    )
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if isFront {
                        HStack(spacing: 4) {
                            if item.isLivePhoto { stackPill("LIVE") }
                            if item.isHdr && !disableHDR { stackPill("HDR") }
                            if item.isGif { stackPill("GIF") }
                            stackPill("\(index + 1)/\(count)")
                        }
                        .padding(10)
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture {
                    guard isFront else { return }
                    handleFrontCardTap(at: index)
                }
                .contextMenu {
                    contextMenuBuilder(item, index)
                }

            if isFront && count > 1 {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy(duration: 0.26)) {
                            activeIndex = (activeIndex - 1 + count) % count
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy(duration: 0.26)) {
                            activeIndex = (activeIndex + 1) % count
                        }
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
                .padding(10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.systemBackground).opacity(isFront ? 0.92 : 0.80), lineWidth: 1.4)
        }
        .shadow(color: .black.opacity(isFront ? 0.14 : 0.08), radius: isFront ? 9 : 5, x: 0, y: 3)
    }

    private func stackPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .foregroundStyle(.primary)
    }

    private func scaleFor(depth: Int) -> CGFloat {
        let base: CGFloat = depth == 0 ? 1.0 : (depth == 1 ? 0.95 : 0.91)
        if depth > 0 {
            let progress = min(1, abs(dragOffset) / 140)
            return base + progress * 0.03
        }
        return base
    }

    private func rotationFor(depth: Int, isFront: Bool) -> Double {
        if isFront {
            return Double(dragOffset) / 22.0
        }
        return depth == 1 ? 4.2 : -4.2
    }

    private func xOffsetFor(depth: Int, isFront: Bool) -> CGFloat {
        if isFront {
            return dragOffset
        }
        return depth == 1 ? 15 : -13
    }

    private func yOffsetFor(depth: Int) -> CGFloat {
        depth == 0 ? 0 : (depth == 1 ? 9 : 16)
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
