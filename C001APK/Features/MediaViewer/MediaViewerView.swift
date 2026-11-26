import CoolapkKit
import os
import Photos
import PhotosUI
import SwiftUI
import UIKit

public struct MediaViewerView: View {
    public let presentation: MediaViewerPresentation

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.zoomNamespace) private var zoomNamespace

    @State private var currentIndex: Int
    @State private var showControls = true
    @State private var loopLivePhoto = false

    public init(presentation: MediaViewerPresentation) {
        self.presentation = presentation
        self._currentIndex = State(initialValue: presentation.initialIndex)
    }

    private var currentItem: FeedMedia {
        presentation.items[currentIndex]
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(presentation.items.enumerated()), id: \.offset) { index, item in
                    MediaPageItemView(
                        item: item,
                        disableHDR: appState.settings.disableHDR,
                        autoPlayLivePhoto: appState.settings.livePhotoAutoPlay,
                        isLoopingLivePhoto: loopLivePhoto && index == currentIndex,
                        onToggleControls: {
                            withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if showControls {
                controlsOverlay
            }
        }
        .statusBarHidden(!showControls)
        .applyZoomTransition(sourceID: presentation.sourceID(at: currentIndex), in: zoomNamespace)
    }

    private var controlsOverlay: some View {
        VStack {
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
                    .foregroundStyle(.white)

                    Spacer()

                    Text("\(currentIndex + 1) / \(presentation.items.count)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .foregroundStyle(.white)

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
                        .foregroundStyle(loopLivePhoto ? Color.accentColor : .white)
                    } else {
                        Color.clear.frame(width: 38, height: 38)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

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
                    .foregroundStyle(.white)

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
                        .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 24)
        }
        .transition(.opacity)
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
    let disableHDR: Bool
    let autoPlayLivePhoto: Bool
    let isLoopingLivePhoto: Bool
    let onToggleControls: () -> Void

    @State private var loadedResult: LoadedImageResult?
    @State private var livePhoto: PHLivePhoto?
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
                .onTapGesture(perform: onToggleControls)
            } else if let loadedResult {
                let isHDR = !disableHDR && (loadedResult.hasHDRGainMap || item.isHdr)
                ZoomableImageScrollView(image: loadedResult.image, preferHDR: isHDR, onSingleTap: onToggleControls)
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
        .task(id: item.id) {
            didFail = false
            loadedResult = await ImagePipeline.shared.loadImage(urlString: item.sourceUrl, maxPixelSize: nil)
            if loadedResult == nil {
                didFail = true
                return
            }
            if item.isLivePhoto, let videoURL = item.videoUrl {
                await loadLivePhoto(imageURL: item.sourceUrl, videoURL: videoURL)
            }
        }
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
