import CoolapkKit
import SwiftUI

public struct RemoteImageView: View {
    public let url: String
    public var maxPixelSize: CGFloat?
    public var contentMode: ContentMode = .fill
    public var honorHDR: Bool = false
    public var onImageLoaded: ((CGSize) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var loaded: LoadedImageResult?
    @State private var loadedKey: String = ""
    @State private var didFail = false

    public init(
        url: String,
        maxPixelSize: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        honorHDR: Bool = false,
        onImageLoaded: ((CGSize) -> Void)? = nil
    ) {
        self.url = coolapkNormalizedURL(url.trimmingCharacters(in: .whitespacesAndNewlines))
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.honorHDR = honorHDR
        self.onImageLoaded = onImageLoaded
    }

    private func resolveActiveLoaded(taskKey: String, shouldHDR: Bool) -> LoadedImageResult? {
        if loadedKey == taskKey, let loaded {
            return loaded
        }
        if let exact = ImagePipeline.cachedImageSync(urlString: url, maxPixelSize: maxPixelSize, preferHDR: shouldHDR) {
            return exact
        }
        if let anyCached = ImagePipeline.cachedAnyImageSync(urlString: url) {
            return anyCached
        }
        return loaded
    }

    public var body: some View {
        let shouldHDR = honorHDR && !appState.settings.disableHDR
        let taskKey = "\(url)|\(Int(maxPixelSize ?? 0))|\(shouldHDR)"
        let activeLoaded = resolveActiveLoaded(taskKey: taskKey, shouldHDR: shouldHDR)

        Group {
            if let activeLoaded {
                let base = Image(uiImage: activeLoaded.image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                if shouldHDR && activeLoaded.hasHDRGainMap {
                    base.allowedDynamicRange(.high)
                } else {
                    base.allowedDynamicRange(.standard)
                }
            } else if didFail {
                Color(.secondarySystemFill)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            } else {
                Color(.secondarySystemFill)
            }
        }
        .task(id: taskKey) {
            guard !url.isEmpty else {
                loadedKey = taskKey
                if loaded == nil {
                    didFail = true
                }
                return
            }
            if let sync = ImagePipeline.cachedImageSync(urlString: url, maxPixelSize: maxPixelSize, preferHDR: shouldHDR) {
                loadedKey = taskKey
                loaded = sync
                didFail = false
                onImageLoaded?(sync.image.size)
                return
            }
            if let anyCached = ImagePipeline.cachedAnyImageSync(urlString: url), loaded == nil {
                loaded = anyCached
                onImageLoaded?(anyCached.image.size)
            }
            didFail = false
            let fetched = await ImagePipeline.shared.loadImage(urlString: url, maxPixelSize: maxPixelSize, preferHDR: shouldHDR)
            guard !Task.isCancelled else { return }
            if let fetched {
                loadedKey = taskKey
                loaded = fetched
                onImageLoaded?(fetched.image.size)
            } else if loaded == nil {
                loadedKey = taskKey
                didFail = true
            }
        }
    }
}

public struct AvatarView: View {
    public let url: String
    public var size: CGFloat = 36

    public init(url: String, size: CGFloat = 36) {
        self.url = coolapkNormalizedURL(url.trimmingCharacters(in: .whitespacesAndNewlines))
        self.size = size
    }

    public var body: some View {
        // Use a unified 240px decode target across all avatar sizes (28pt..64pt) so navigating
        // from feed rows, comments, or chat bubbles into UserDetailView always hits NSCache synchronously.
        RemoteImageView(url: url, maxPixelSize: 240)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}
