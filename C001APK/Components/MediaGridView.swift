import CoolapkKit
import SwiftUI

public struct MediaGridView: View {
    public let items: [FeedMedia]
    public var onTapItem: ((Int) -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var activeCardIndex: Int? = 0

    public init(items: [FeedMedia], onTapItem: ((Int) -> Void)? = nil) {
        self.items = items
        self.onTapItem = onTapItem
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else if items.count == 1 {
            singleImage(items[0], index: 0)
        } else if appState.settings.mediaDisplayStyle == .stackedCards {
            stackedCardsView(items)
        } else {
            gridView(items)
        }
    }

    private func stackedCardsView(_ items: [FeedMedia]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let sourceID = onTapItem == nil ? "media-\(transitionSeed)-\(index)" : nil
                    Button {
                        triggerTap(at: index)
                    } label: {
                        Color.clear
                            .frame(height: 224)
                            .overlay {
                                RemoteImageView(
                                    url: item.thumbnailUrl,
                                    maxPixelSize: 1080
                                )
                            }
                            .overlay(alignment: .topTrailing) {
                                HStack(spacing: 4) {
                                    if item.isLivePhoto { badgePill("LIVE") }
                                    if item.isHdr && !appState.settings.disableHDR { badgePill("HDR") }
                                    if item.isGif { badgePill("GIF") }
                                    badgePill("\(index + 1)/\(items.count)")
                                }
                                .padding(8)
                                .allowsHitTesting(false)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            }
                            .containerRelativeFrame(.horizontal) { width, _ in
                                max(200, width - 22)
                            }
                            .applyZoomSource(id: sourceID, in: zoomNamespace)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.93)
                                    .rotationEffect(.degrees(phase.value * -2.2))
                                    .opacity(phase.isIdentity ? 1.0 : 0.82)
                            }
                    }
                    .buttonStyle(.plain)
                    .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.trailing, 18)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $activeCardIndex)
        .scrollClipDisabled()
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
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .applyZoomSource(id: sourceID, in: zoomNamespace)
                    }
                    .buttonStyle(.plain)

                    badgeStack(for: item)

                    if index == 8 && items.count > 9 {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .applyZoomSource(id: sourceID, in: zoomNamespace)

                badgeStack(for: item, isLong: (ratio < 0.42))
            }
        }
        .buttonStyle(.plain)
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
        // Matches Coolapk dimension suffixes like _1080x1920.jpg or @1080x1920
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
