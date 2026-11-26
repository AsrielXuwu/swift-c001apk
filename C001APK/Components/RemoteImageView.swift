import SwiftUI

public struct RemoteImageView: View {
    public let url: String
    public var maxPixelSize: CGFloat?
    public var contentMode: ContentMode = .fill
    public var honorHDR: Bool = false

    @Environment(AppState.self) private var appState
    @State private var loaded: LoadedImageResult?
    @State private var didFail = false

    public init(
        url: String,
        maxPixelSize: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        honorHDR: Bool = false
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.honorHDR = honorHDR
    }

    public var body: some View {
        Group {
            if let loaded {
                let base = Image(uiImage: loaded.image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                if honorHDR && loaded.hasHDRGainMap && !appState.settings.disableHDR {
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
        .task(id: "\(url)|\(Int(maxPixelSize ?? 0))") {
            guard !url.isEmpty else {
                didFail = true
                return
            }
            didFail = false
            loaded = await ImagePipeline.shared.loadImage(urlString: url, maxPixelSize: maxPixelSize)
            if loaded == nil && !Task.isCancelled {
                didFail = true
            }
        }
    }
}

public struct AvatarView: View {
    public let url: String
    public var size: CGFloat = 36

    public init(url: String, size: CGFloat = 36) {
        self.url = url
        self.size = size
    }

    public var body: some View {
        RemoteImageView(url: url, maxPixelSize: size * 3)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}
