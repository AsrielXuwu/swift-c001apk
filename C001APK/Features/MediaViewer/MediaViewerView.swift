import CoolapkKit
import CoreGraphics
import os
import Photos
import PhotosUI
import SwiftUI
import UIKit

private struct MediaContrastState: Equatable, Sendable {
    var topIsLight: Bool = false
    var bottomIsLight: Bool = false
}

public struct MediaViewerView: View {
    public let presentation: MediaViewerPresentation

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zoomNamespace) private var zoomNamespace

    @State private var currentIndex: Int
    @State private var scrolledIndex: Int?
    @State private var showControls = true
    @State private var loopLivePhoto = false
    @State private var contrastByIndex: [Int: MediaContrastState] = [:]

    public init(presentation: MediaViewerPresentation) {
        self.presentation = presentation
        self._currentIndex = State(initialValue: presentation.initialIndex)
        self._scrolledIndex = State(initialValue: presentation.initialIndex)
    }

    private var currentItem: FeedMedia {
        presentation.items[currentIndex]
    }

    private var currentContrast: MediaContrastState {
        contrastByIndex[currentIndex] ?? MediaContrastState()
    }

    public var body: some View {
        GeometryReader { safeGeo in
            let safeInsets = safeGeo.safeAreaInsets
            let totalWidth = safeGeo.size.width + safeInsets.leading + safeInsets.trailing
            let totalHeight = safeGeo.size.height + safeInsets.top + safeInsets.bottom
            let containerSize = CGSize(width: totalWidth, height: totalHeight)

            ZStack {
                Color.black.ignoresSafeArea(.all)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(presentation.items.enumerated()), id: \.offset) { index, item in
                            MediaPageItemView(
                                item: item,
                                containerSize: containerSize,
                                disableHDR: appState.settings.disableHDR,
                                autoPlayLivePhoto: appState.settings.livePhotoAutoPlay,
                                isLoopingLivePhoto: loopLivePhoto && index == currentIndex,
                                onToggleControls: {
                                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                                },
                                onContrastDetected: { contrast in
                                    if contrastByIndex[index] != contrast {
                                        contrastByIndex[index] = contrast
                                    }
                                }
                            )
                            .frame(width: containerSize.width, height: containerSize.height)
                            .ignoresSafeArea(.all)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $scrolledIndex)
                .ignoresSafeArea(.all)
                .onChange(of: scrolledIndex) { _, newValue in
                    if let newValue, (0..<presentation.items.count).contains(newValue), newValue != currentIndex {
                        currentIndex = newValue
                    }
                }

                if showControls {
                    controlsOverlay(safeInsets: safeInsets)
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .ignoresSafeArea(.all)
        }
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(showControls ? .automatic : .hidden)
        .onAppear {
            if appState.settings.livePhotoLoopPlay {
                loopLivePhoto = true
            }
        }
        .applyZoomTransition(sourceID: presentation.sourceID(at: currentIndex), in: zoomNamespace)
    }

    private func controlsOverlay(safeInsets: EdgeInsets) -> some View {
        let topTint: Color = currentContrast.topIsLight ? .black : .white
        let bottomTint: Color = currentContrast.bottomIsLight ? .black : .white
        let effectiveTop = max(resolvedTopSafeInset(from: safeInsets), 44)
        let effectiveBottom = max(resolvedBottomSafeInset(from: safeInsets), 20)

        return VStack {
            GlassEffectContainer(spacing: 12) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .foregroundStyle(topTint)

                    Spacer()

                    Text("\(currentIndex + 1) / \(presentation.items.count)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .foregroundStyle(topTint)

                    Spacer()

                    if currentItem.isLivePhoto {
                        Button {
                            loopLivePhoto.toggle()
                        } label: {
                            Label(loopLivePhoto ? "循环中" : "实况", systemImage: "livephoto")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .foregroundStyle(loopLivePhoto ? Color.accentColor : topTint)
                    } else {
                        Color.clear.frame(width: 38, height: 38)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, effectiveTop + 6)

            Spacer()

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        Task { await saveMedia(item: currentItem) }
                    } label: {
                        Label(currentItem.isLivePhoto ? "保存实况原件" : "保存原图", systemImage: "arrow.down.to.line")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .foregroundStyle(bottomTint)

                    if presentation.items.count > 1 {
                        Button {
                            Task { await saveAllMedia() }
                        } label: {
                            Label("保存全部", systemImage: "square.stack.3d.down.right")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .foregroundStyle(bottomTint)
                    }

                    Button {
                        UIPasteboard.general.string = currentItem.sourceUrl
                        appState.showToast("已复制图片链接")
                    } label: {
                        Image(systemName: "link")
                            .font(.body)
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .foregroundStyle(bottomTint)
                }
            }
            .padding(.bottom, effectiveBottom + 8)
        }
        .ignoresSafeArea(.all)
        .transition(.opacity)
    }

    private func resolvedTopSafeInset(from safeInsets: EdgeInsets) -> CGFloat {
        if safeInsets.top > 0 { return safeInsets.top }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.keyWindow?.safeAreaInsets.top
            ?? scenes.first?.windows.first?.safeAreaInsets.top
            ?? 48
    }

    private func resolvedBottomSafeInset(from safeInsets: EdgeInsets) -> CGFloat {
        if safeInsets.bottom > 0 { return safeInsets.bottom }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.keyWindow?.safeAreaInsets.bottom
            ?? scenes.first?.windows.first?.safeAreaInsets.bottom
            ?? 20
    }

    private func saveMedia(item: FeedMedia) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            appState.showToast("请在系统设置中允许访问相册")
            return
        }

        if item.isLivePhoto, let videoURLString = item.videoUrl {
            guard let imgFile = await ImagePipeline.shared.downloadToTemporaryFile(urlString: item.sourceUrl, defaultExtension: "jpg"),
                  let vidFile = await ImagePipeline.shared.downloadToTemporaryFile(urlString: videoURLString, defaultExtension: "mov") else {
                appState.showToast("实况原件下载失败")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, fileURL: imgFile, options: nil)
                    req.addResource(with: .pairedVideo, fileURL: vidFile, options: nil)
                }
                appState.showToast("已保存实况照片到相册")
            } catch {
                appState.showToast("保存失败：\(error.localizedDescription)")
            }
            return
        }

        guard let data = await ImagePipeline.shared.fetchRawData(urlString: item.sourceUrl) else {
            appState.showToast("原图下载失败")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }
            appState.showToast("已保存原图到相册")
        } catch {
            appState.showToast("保存失败：\(error.localizedDescription)")
        }
    }

    private func saveAllMedia() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            appState.showToast("请在系统设置中允许访问相册")
            return
        }
        var savedCount = 0
        for item in presentation.items {
            if let data = await ImagePipeline.shared.fetchRawData(urlString: item.sourceUrl) {
                try? await PHPhotoLibrary.shared().performChanges {
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, data: data, options: nil)
                }
                savedCount += 1
            }
        }
        appState.showToast("已保存 \(savedCount) 张图片到相册")
    }
}

private struct MediaPageItemView: View {
    let item: FeedMedia
    let containerSize: CGSize
    let disableHDR: Bool
    let autoPlayLivePhoto: Bool
    let isLoopingLivePhoto: Bool
    let onToggleControls: () -> Void
    let onContrastDetected: (MediaContrastState) -> Void

    @State private var loadedResult: LoadedImageResult?
    @State private var livePhoto: PHLivePhoto?
    @State private var gifData: Data?
    @State private var liveAutoPlayTrigger = 0
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let livePhoto {
                LivePhotoRepresentable(
                    livePhoto: livePhoto,
                    autoPlayTrigger: liveAutoPlayTrigger,
                    isLooping: isLoopingLivePhoto
                )
                .ignoresSafeArea(.all)
                .onTapGesture(perform: onToggleControls)
            } else if let gifData, item.isGif {
                AnimatedGIFView(data: gifData, contentMode: .scaleAspectFit)
                    .ignoresSafeArea(.all)
                    .onTapGesture(perform: onToggleControls)
            } else if let loadedResult {
                let isHDR = !disableHDR && (loadedResult.hasHDRGainMap || item.isHdr)
                ZoomableImageScrollView(image: loadedResult.image, preferHDR: isHDR, onSingleTap: onToggleControls)
                    .ignoresSafeArea(.all)
            } else if didFail {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("图片加载失败")
                        .foregroundStyle(.secondary)
                }
                .onTapGesture(perform: onToggleControls)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .ignoresSafeArea(.all)
        .task(id: item.id) {
            didFail = false
            if item.isGif {
                gifData = await ImagePipeline.shared.fetchRawData(urlString: item.sourceUrl)
            }
            let result = await ImagePipeline.shared.loadImage(urlString: item.sourceUrl, maxPixelSize: nil)
            loadedResult = result
            if let result {
                if let cgImage = result.image.cgImage {
                    let imageSize = result.image.size
                    let size = containerSize
                    let detected = await Task.detached(priority: .utility) {
                        Self.detectContrast(cgImage: cgImage, imageSize: imageSize, containerSize: size)
                    }.value
                    onContrastDetected(detected)
                }
                if item.isLivePhoto, let videoURL = item.videoUrl {
                    await loadLivePhoto(imageURL: item.sourceUrl, videoURL: videoURL)
                }
            } else {
                didFail = true
            }
        }
    }

    nonisolated private static func detectContrast(
        cgImage: CGImage,
        imageSize: CGSize,
        containerSize: CGSize
    ) -> MediaContrastState {
        guard containerSize.width > 0, containerSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else {
            return MediaContrastState()
        }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let drawnW = imageSize.width * scale
        let drawnH = imageSize.height * scale
        let drawnRect = CGRect(
            x: (containerSize.width - drawnW) * 0.5,
            y: (containerSize.height - drawnH) * 0.5,
            width: drawnW,
            height: drawnH
        )

        let topBarRect = CGRect(x: 16, y: 12, width: containerSize.width - 32, height: 84)
        let bottomBarRect = CGRect(
            x: max(16, containerSize.width * 0.12),
            y: containerSize.height - 96,
            width: containerSize.width * 0.76,
            height: 68
        )

        let topLight = averageLuminance(
            cgImage: cgImage,
            screenZone: topBarRect,
            drawnRect: drawnRect
        ) > 0.62
        let bottomLight = averageLuminance(
            cgImage: cgImage,
            screenZone: bottomBarRect,
            drawnRect: drawnRect
        ) > 0.62

        return MediaContrastState(topIsLight: topLight, bottomIsLight: bottomLight)
    }

    nonisolated private static func averageLuminance(
        cgImage: CGImage,
        screenZone: CGRect,
        drawnRect: CGRect
    ) -> Double {
        let overlap = screenZone.intersection(drawnRect)
        guard !overlap.isNull,
              overlap.width > 4,
              overlap.height > 4,
              (overlap.width * overlap.height) >= (screenZone.width * screenZone.height * 0.25) else {
            return 0.0
        }

        let normX = max(0, min(1, (overlap.minX - drawnRect.minX) / drawnRect.width))
        let normY = max(0, min(1, (overlap.minY - drawnRect.minY) / drawnRect.height))
        let normW = max(0.01, min(1 - normX, overlap.width / drawnRect.width))
        let normH = max(0.01, min(1 - normY, overlap.height / drawnRect.height))

        let pixelW = CGFloat(cgImage.width)
        let pixelH = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: normX * pixelW,
            y: normY * pixelH,
            width: normW * pixelW,
            height: normH * pixelH
        ).integral

        guard cropRect.width >= 1, cropRect.height >= 1,
              let cropped = cgImage.cropping(to: cropRect) else {
            return 0.0
        }

        let sampleSize = 8
        var rgba = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0.0
        }
        ctx.interpolationQuality = .low
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var sum: Double = 0
        let count = Double(sampleSize * sampleSize)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let r = Double(rgba[i]) / 255.0
            let g = Double(rgba[i + 1]) / 255.0
            let b = Double(rgba[i + 2]) / 255.0
            sum += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return sum / count
    }

    private func loadLivePhoto(imageURL: String, videoURL: String) async {
        guard let imgFile = await ImagePipeline.shared.downloadToTemporaryFile(urlString: imageURL, defaultExtension: "jpg"),
              let vidFile = await ImagePipeline.shared.downloadToTemporaryFile(urlString: videoURL, defaultExtension: "mov") else {
            return
        }
        let placeholder = loadedResult?.image
        let resumedLock = OSAllocatedUnfairLock(initialState: false)
        let box: LivePhotoBox = await withCheckedContinuation { continuation in
            PHLivePhoto.request(
                withResourceFileURLs: [imgFile, vidFile],
                placeholderImage: placeholder,
                targetSize: .zero,
                contentMode: .aspectFit
            ) { photo, info in
                let isDegraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                guard !isDegraded || photo == nil else { return }
                let shouldResume = resumedLock.withLock { state -> Bool in
                    guard !state else { return false }
                    state = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: LivePhotoBox(photo: photo))
                }
            }
        }
        if let assembled = box.photo {
            livePhoto = assembled
            if autoPlayLivePhoto {
                liveAutoPlayTrigger += 1
            }
        }
    }
}

private struct LivePhotoBox: @unchecked Sendable {
    let photo: PHLivePhoto?
}
