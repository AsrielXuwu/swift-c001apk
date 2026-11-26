import Photos
import PhotosUI
import SwiftUI
import UIKit

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

    public func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .clear
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 6.0
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true
        scroll.delegate = context.coordinator

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.preferredImageDynamicRange = preferHDR ? .high : .standard
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = scroll.bounds
        scroll.addSubview(imageView)
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

    public func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.imageView?.preferredImageDynamicRange = preferHDR ? .high : .standard
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            uiView.zoomScale = 1.0
        }
    }

    @MainActor
    public final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        var onSingleTap: () -> Void

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
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
