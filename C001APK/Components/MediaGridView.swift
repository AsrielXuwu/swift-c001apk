import CoolapkKit
import SwiftUI

public struct MediaGridView: View {
    public let items: [FeedMedia]
    public let onTapItem: (Int) -> Void

    @Environment(AppState.self) private var appState

    public init(items: [FeedMedia], onTapItem: @escaping (Int) -> Void) {
        self.items = items
        self.onTapItem = onTapItem
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else if items.count == 1 {
            singleImage(items[0], index: 0)
        } else {
            let displayItems = Array(items.prefix(9))
            let columnCount = displayItems.count == 2 || displayItems.count == 4 ? 2 : 3
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(displayItems.enumerated()), id: \.offset) { index, item in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            onTapItem(index)
                        } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    RemoteImageView(
                                        url: item.thumbnailUrl,
                                        maxPixelSize: 420
                                    )
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        badgeStack(for: item)

                        if index == 8 && items.count > 9 {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    }

    private func singleImage(_ item: FeedMedia, index: Int) -> some View {
        Button {
            onTapItem(index)
        } label: {
            ZStack(alignment: .topTrailing) {
                RemoteImageView(
                    url: item.thumbnailUrl,
                    maxPixelSize: 1080,
                    contentMode: .fill,
                    honorHDR: false
                )
                .frame(maxWidth: 320, minHeight: 140, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }

                badgeStack(for: item)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badgeStack(for item: FeedMedia) -> some View {
        let showLive = item.isLivePhoto
        let showHDR = item.isHdr && !appState.settings.disableHDR
        let showGIF = item.isGif

        if showLive || showHDR || showGIF {
            HStack(spacing: 4) {
                if showLive {
                    badgePill("LIVE")
                }
                if showHDR {
                    badgePill("HDR")
                }
                if showGIF {
                    badgePill("GIF")
                }
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
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
    }
}
