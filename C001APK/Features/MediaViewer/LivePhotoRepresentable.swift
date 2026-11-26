import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

public final class LiveVideoContainerView: UIView {
    public override class var layerClass: AnyClass { AVPlayerLayer.self }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

public struct LiveVideoPlayerView: UIViewRepresentable {
    public let videoURL: URL
    public let playTrigger: Int
    public let isLooping: Bool
    public let isMuted: Bool
    public var videoGravity: AVLayerVideoGravity = .resizeAspect
    public let onReadyToDisplay: (() -> Void)?
    public let onPlaybackEnded: (() -> Void)?

    public init(
        videoURL: URL,
        playTrigger: Int,
        isLooping: Bool,
        isMuted: Bool = false,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        onReadyToDisplay: (() -> Void)? = nil,
        onPlaybackEnded: (() -> Void)? = nil
    ) {
        self.videoURL = videoURL
        self.playTrigger = playTrigger
        self.isLooping = isLooping
        self.isMuted = isMuted
        self.videoGravity = videoGravity
        self.onReadyToDisplay = onReadyToDisplay
        self.onPlaybackEnded = onPlaybackEnded
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onReadyToDisplay: onReadyToDisplay, onPlaybackEnded: onPlaybackEnded)
    }

    public func makeUIView(context: Context) -> LiveVideoContainerView {
        let view = LiveVideoContainerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = videoGravity
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        return view
    }

    public func updateUIView(_ uiView: LiveVideoContainerView, context: Context) {
        uiView.playerLayer.videoGravity = videoGravity
        context.coordinator.onReadyToDisplay = onReadyToDisplay
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.isLooping = isLooping

        if context.coordinator.loadedURL != videoURL {
            context.coordinator.load(url: videoURL, onto: uiView.playerLayer)
        }
        context.coordinator.player?.isMuted = isMuted

        if context.coordinator.lastPlayTrigger != playTrigger {
            context.coordinator.lastPlayTrigger = playTrigger
            context.coordinator.restart()
        } else if isLooping && !context.coordinator.wasLooping {
            context.coordinator.restart()
        }
        context.coordinator.wasLooping = isLooping
    }

    public static func dismantleUIView(_ uiView: LiveVideoContainerView, coordinator: Coordinator) {
        coordinator.teardown(layer: uiView.playerLayer)
    }

    @MainActor
    public final class Coordinator: NSObject {
        var player: AVPlayer?
        var loadedURL: URL?
        var lastPlayTrigger: Int = -1
        var isLooping = false
        var wasLooping = false
        var onReadyToDisplay: (() -> Void)?
        var onPlaybackEnded: (() -> Void)?
        private var endObserver: NSObjectProtocol?
        private var readyObservation: NSKeyValueObservation?

        init(onReadyToDisplay: (() -> Void)?, onPlaybackEnded: (() -> Void)?) {
            self.onReadyToDisplay = onReadyToDisplay
            self.onPlaybackEnded = onPlaybackEnded
        }

        func load(url: URL, onto layer: AVPlayerLayer) {
            teardown(layer: layer)
            loadedURL = url
            let item = AVPlayerItem(url: url)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.actionAtItemEnd = .none
            layer.player = newPlayer
            player = newPlayer

            readyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] observedLayer, _ in
                if observedLayer.isReadyForDisplay {
                    Task { @MainActor [weak self] in
                        self?.onReadyToDisplay?()
                    }
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.isLooping {
                        self.player?.seek(to: .zero)
                        self.player?.play()
                    } else {
                        self.onPlaybackEnded?()
                    }
                }
            }
        }

        func restart() {
            guard let player else { return }
            player.seek(to: .zero) { _ in
                Task { @MainActor in
                    player.play()
                }
            }
        }

        func teardown(layer: AVPlayerLayer) {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            readyObservation?.invalidate()
            readyObservation = nil
            player?.pause()
            layer.player = nil
            player = nil
            loadedURL = nil
        }
    }
}

public struct LivePhotoRepresentable: UIViewRepresentable {
    public let livePhoto: PHLivePhoto
    public let autoPlayTrigger: Int
    public let isLooping: Bool

    public init(livePhoto: PHLivePhoto, autoPlayTrigger: Int, isLooping: Bool) {
        self.livePhoto = livePhoto
        self.autoPlayTrigger = autoPlayTrigger
        self.isLooping = isLooping
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        view.clipsToBounds = false
        view.delegate = context.coordinator
        return view
    }

    public func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        context.coordinator.isLooping = isLooping
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
        }
        if context.coordinator.lastTrigger != autoPlayTrigger {
            context.coordinator.lastTrigger = autoPlayTrigger
            uiView.startPlayback(with: .full)
        }
        if isLooping && !context.coordinator.wasLooping {
            uiView.startPlayback(with: .full)
        } else if !isLooping && context.coordinator.wasLooping {
            uiView.stopPlayback()
        }
        context.coordinator.wasLooping = isLooping
    }

    @MainActor
    public final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var lastTrigger: Int = -1
        var isLooping = false
        var wasLooping = false

        public func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            if isLooping {
                livePhotoView.startPlayback(with: .full)
            }
        }
    }
}

public final class ZoomContainerScrollView: UIScrollView {
    weak var zoomedImageView: UIImageView?

    public override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale <= 1.001, let zoomedImageView {
            zoomedImageView.frame = bounds
            contentSize = bounds.size
        }
    }
}

public struct ZoomableImageScrollView: UIViewRepresentable {
    public let image: UIImage
    public var preferHDR: Bool = false
    public let onSingleTap: () -> Void

    public init(image: UIImage, preferHDR: Bool = false, onSingleTap: @escaping () -> Void) {
        self.image = image
        self.preferHDR = preferHDR
        self.onSingleTap = onSingleTap
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    public func makeUIView(context: Context) -> ZoomContainerScrollView {
        let scroll = ZoomContainerScrollView()
        scroll.backgroundColor = .clear
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 6.0
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.isScrollEnabled = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.preferredImageDynamicRange = preferHDR ? .high : .standard
        imageView.frame = scroll.bounds
        scroll.addSubview(imageView)
        scroll.zoomedImageView = imageView
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scroll

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scroll.addGestureRecognizer(singleTap)

        return scroll
    }

    public func updateUIView(_ uiView: ZoomContainerScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.imageView?.preferredImageDynamicRange = preferHDR ? .high : .standard
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            uiView.zoomScale = 1.0
            uiView.isScrollEnabled = false
            uiView.setNeedsLayout()
        }
    }

    @MainActor
    public final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: ZoomContainerScrollView?
        var onSingleTap: () -> Void

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        public func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.isScrollEnabled = scrollView.zoomScale > 1.01
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.05 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 2.5, height: scrollView.bounds.height / 2.5)
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}
