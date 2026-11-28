import CoolapkKit
import SwiftUI

public struct HomeRowRenderer: View {
    public let row: HomeFeedRow
    public var onSelectFeed: ((FeedItem) -> Void)?

    @Environment(AppState.self) private var appState

    public init(row: HomeFeedRow, onSelectFeed: ((FeedItem) -> Void)? = nil) {
        self.row = row
        self.onSelectFeed = onSelectFeed
    }

    public var body: some View {
        switch row {
        case let .feed(feed):
            if shouldShowFeed(feed) {
                FeedRowView(feed: feed, onSelectFeed: onSelectFeed.map { callback in { callback(feed) } })
            }

        case let .product(product):
            ProductRowView(product: product)

        case let .topic(topic):
            TopicRowView(topic: topic)

        case let .user(user):
            if !appState.blacklist.isUserBlocked(user.id) && appState.contentFilter.match(user: user) == nil {
                UserRowView(user: user)
            }

        case let .app(app):
            AppRowView(app: app)

        case let .banners(_, banners):
            BannerCarouselView(banners: banners)

        case let .icons(_, links):
            IconLinksScrollView(links: links)

        case let .sections(_, sections):
            ImageTextSectionsView(sections: sections)

        case let .sectionTitle(_, title, url, subtitle):
            SectionHeaderRow(title: title, subtitle: subtitle, url: url)

        case let .linkBar(_, sections), let .linkList(_, sections), let .columnTabs(_, sections):
            LinkBarRowView(sections: sections)

        case let .text(_, text), let .notice(_, text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .c001CardStyle(cornerRadius: 14)
                .padding(.horizontal, 12)

        case let .loginPrompt(_, title):
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("去登录") {
                    appState.showLoginSheet = true
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: .capsule)
                .foregroundStyle(Color.accentColor)
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 16)
            .padding(.horizontal, 12)

        case let .goods(_, items):
            GoodsStripView(items: items)

        case let .lives(_, items):
            LivesStripView(items: items)

        case let .browse(item):
            BrowseRowView(item: item)

        case let .collection(item):
            CollectionRowView(item: item)

        case let .event(item):
            EventRowView(event: item)

        case let .dyh(item):
            DyhRowView(dyh: item)

        case let .goodsRanking(item):
            GoodsRankingCardView(item: item)
        }
    }

    private func shouldShowFeed(_ feed: FeedItem) -> Bool {
        if appState.blacklist.isUserBlocked(feed.uid) { return false }
        let blockedTopics = appState.blacklist.blockedTopicSet
        if !blockedTopics.isEmpty && !blockedTopics.isDisjoint(with: Set(feed.topicTags)) {
            return false
        }
        return appState.contentFilter.match(feed: feed) == nil
    }
}

// MARK: - Specific Card Views

struct BannerCarouselView: View {
    let banners: [HomeBanner]
    @Environment(AppState.self) private var appState
    @State private var deckPhase: CGFloat = 0
    @State private var dragProgress: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var lastDragEndedAt: Date = .distantPast
    @State private var availableWidth: CGFloat = 360
    @State private var detectedRatios: [Int: CGFloat] = [:]

    private var currentNearestIndex: Int {
        let count = banners.count
        guard count > 0 else { return 0 }
        let rounded = Int((deckPhase + dragProgress).rounded())
        return ((rounded % count) + count) % count
    }

    private let bannerCropAspectRatio: CGFloat = 4.5

    private func cardSize(at index: Int, maxStageWidth: CGFloat) -> CGSize {
        let width = max(160, round(maxStageWidth))
        let height = max(56, round(width / bannerCropAspectRatio))
        return CGSize(width: width, height: height)
    }

    private func updateDetectedRatio(index: Int, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let ratio = size.width / size.height
        if let existing = detectedRatios[index], abs(existing - ratio) < 0.01 { return }
        detectedRatios[index] = ratio
    }

    var body: some View {
        if banners.isEmpty {
            EmptyView()
        } else {
            let count = banners.count
            let visibleLayers = min(count, 3)
            let activeIdx = currentNearestIndex
            let leftInset: CGFloat = visibleLayers > 2 ? 24 : 12
            let rightInset: CGFloat = visibleLayers > 1 ? 24 : 12
            let bottomInset: CGFloat = visibleLayers > 1 ? 15 : 0
            let stageWidth = max(180, availableWidth - leftInset - rightInset)
            let activeCardSize = cardSize(at: activeIdx, maxStageWidth: stageWidth)
            let maxCardHeight = (0..<count).map { cardSize(at: $0, maxStageWidth: stageWidth).height }.max() ?? 184

            ZStack {
                OrbitalDeckStage(
                    phase: deckPhase + dragProgress,
                    count: count,
                    cardHeight: maxCardHeight
                ) { idx, isFront in
                    let banner = banners[idx]
                    let itemSize = cardSize(at: idx, maxStageWidth: stageWidth)
                    Color(.secondarySystemGroupedBackground)
                        .frame(width: itemSize.width, height: itemSize.height)
                        .overlay {
                            RemoteImageView(url: banner.image, maxPixelSize: 1200, contentMode: .fill) { size in
                                updateDetectedRatio(index: idx, size: size)
                            }
                            .frame(width: itemSize.width, height: itemSize.height)
                            .clipped()
                            .allowsHitTesting(false)
                        }
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            if !banner.title.isEmpty || !banner.subtitle.isEmpty {
                                ZStack(alignment: .bottomLeading) {
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.72)],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        if !banner.title.isEmpty {
                                            Text(banner.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                        }
                                        if !banner.subtitle.isEmpty {
                                            Text(banner.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.85))
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .padding(.trailing, count > 1 ? 66 : 12)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.4)
                        }
                        .onTapGesture {
                            guard isFront,
                                  !isHorizontalDragging,
                                  abs(dragProgress) < 0.04,
                                  Date().timeIntervalSince(lastDragEndedAt) > 0.30,
                                  !banner.url.isEmpty else { return }
                            appState.openRawLink(banner.url, title: banner.title)
                        }
                }
                .padding(.leading, leftInset)
                .padding(.trailing, rightInset)
                .padding(.bottom, bottomInset)

                if count > 1 {
                    HorizontalDeckPanOverlay(
                        isEnabled: count > 1,
                        activeCardSize: activeCardSize,
                        onTap: {
                            guard !isHorizontalDragging,
                                  abs(dragProgress) < 0.04,
                                  Date().timeIntervalSince(lastDragEndedAt) > 0.30,
                                  banners.indices.contains(activeIdx) else { return }
                            let banner = banners[activeIdx]
                            if !banner.url.isEmpty {
                                appState.openRawLink(banner.url, title: banner.title)
                            }
                        },
                        onDragChanged: { dx in
                            if !isHorizontalDragging {
                                isHorizontalDragging = true
                            }
                            dragProgress = max(-1.15, min(1.15, -dx / 210.0))
                        },
                        onDragEnded: { dx, predicted, cancelled in
                            lastDragEndedAt = Date()
                            isHorizontalDragging = false
                            guard !cancelled else {
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
                    .frame(height: maxCardHeight)
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)
                    .padding(.bottom, bottomInset)

                    VStack {
                        HStack {
                            Spacer()
                            Text("\(activeIdx + 1)/\(count)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                                .foregroundStyle(.primary)
                        }
                        .allowsHitTesting(false)

                        Spacer()

                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Button {
                                    stepDeck(by: -1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    stepDeck(by: 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .frame(width: 22, height: 22)
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
                    .padding(10)
                    .frame(width: activeCardSize.width, height: activeCardSize.height)
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)
                    .padding(.bottom, bottomInset)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: visibleLayers > 1 ? maxCardHeight + bottomInset + 2 : maxCardHeight)
            .animation(.interpolatingSpring(stiffness: 220, damping: 24), value: maxCardHeight)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { _, newWidth in
                if newWidth > 80, abs(newWidth - availableWidth) > 2 {
                    availableWidth = newWidth
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func stepDeck(by delta: CGFloat) {
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 24)) {
            deckPhase = deckPhase.rounded() + delta
        }
    }
}

struct SingleImageLinkCardView: View {
    let imageURL: String
    let title: String
    let subtitle: String
    let targetURL: String

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var detectedRatio: CGFloat?
    @State private var transitionSeed = UUID().uuidString

    private var effectiveAspectRatio: CGFloat {
        let raw = detectedRatio ?? MediaGridView.inferredAspectRatio(from: imageURL) ?? 2.2
        return max(0.5, min(raw, 5.0))
    }

    var body: some View {
        let tid = "singleimg-\(transitionSeed)"
        Button {
            if !targetURL.isEmpty {
                appState.openRawLink(targetURL, title: title, transitionID: tid)
            }
        } label: {
            Color(.secondarySystemGroupedBackground)
                .aspectRatio(effectiveAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    RemoteImageView(url: imageURL, maxPixelSize: 1200, contentMode: .fit) { size in
                        guard size.width > 0, size.height > 0 else { return }
                        let ratio = size.width / size.height
                        if let existing = detectedRatio, abs(existing - ratio) < 0.01 { return }
                        detectedRatio = ratio
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if !title.isEmpty || !subtitle.isEmpty {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.72)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                if !title.isEmpty {
                                    Text(title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                }
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.86))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.4)
                }
                .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 20)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct IconLinksScrollView: View {
    public let links: [HomeIconLink]
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var detectedRatios: [String: CGFloat] = [:]

    public init(links: [HomeIconLink]) { self.links = links }

    private func aspectRatio(for link: HomeIconLink) -> CGFloat {
        let raw = detectedRatios[link.id]
            ?? MediaGridView.inferredAspectRatio(from: link.image)
            ?? 1.0
        return max(1.0, min(raw, 2.8))
    }

    public static func isWideIconURL(_ url: String) -> Bool {
        if let ratio = MediaGridView.inferredAspectRatio(from: url), ratio >= 1.45 {
            return true
        }
        return false
    }

    private var isRankedGrid: Bool {
        links.contains(where: { $0.rank > 0 || !$0.hotText.isEmpty }) && links.count >= 3
    }

    private var isMultiRowCategoryGrid: Bool {
        !isRankedGrid
            && links.count >= 5
            && links.count <= 15
            && links.allSatisfy { $0.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !Self.isWideIconURL($0.image) }
    }

    public var body: some View {
        if links.count == 1, let single = links.first, !single.image.isEmpty {
            SingleImageLinkCardView(
                imageURL: single.image,
                title: single.title,
                subtitle: single.subtitle,
                targetURL: single.url
            )
        } else if isRankedGrid {
            rankedGridBody
                .c001CardStyle(cornerRadius: 20)
                .padding(.horizontal, 12)
        } else if isMultiRowCategoryGrid {
            categoryGridBody
                .c001CardStyle(cornerRadius: 20)
                .padding(.horizontal, 12)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(links) { link in
                        let ratio = aspectRatio(for: link)
                        let iconHeight: CGFloat = 44
                        let iconWidth: CGFloat = round(iconHeight * ratio)
                        let labelWidth: CGFloat = max(58, iconWidth)
                        let sourceID = "iconlink-\(transitionSeed)-\(link.id)"
                        Button {
                            if !link.url.isEmpty {
                                appState.openRawLink(link.url, title: link.title, transitionID: sourceID)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                RemoteImageView(url: link.image, maxPixelSize: 260, contentMode: .fit) { size in
                                    guard size.width > 0, size.height > 0 else { return }
                                    let r = size.width / size.height
                                    if let existing = detectedRatios[link.id], abs(existing - r) < 0.02 { return }
                                    detectedRatios[link.id] = r
                                }
                                .frame(width: iconWidth, height: iconHeight)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                if !link.title.isEmpty {
                                    Text(link.title)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: labelWidth)
                                }
                            }
                            .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }

    private var rankedGridBody: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(4, max(2, links.count)))
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(Array(links.enumerated()), id: \.element.id) { idx, item in
                let rank = item.rank > 0 ? item.rank : (idx + 1)
                let sourceID = "iconrank-\(transitionSeed)-\(item.id)"
                Button {
                    if !item.url.isEmpty {
                        appState.openRawLink(item.url, title: item.title, transitionID: sourceID)
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            RemoteImageView(url: item.image, maxPixelSize: 220, contentMode: .fit)
                                .frame(height: 58)
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                            if rank <= 4 {
                                Text("TOP \(rank)")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(rankBadgeColor(rank), in: Capsule())
                                    .padding(4)
                            }
                        }

                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !item.hotText.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                                Text(item.hotText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 13)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var categoryGridBody: some View {
        let colCount = links.count % 5 == 0 ? 5 : (links.count % 4 == 0 ? 4 : 5)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: colCount)
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(links) { item in
                let sourceID = "icongrid-\(transitionSeed)-\(item.id)"
                Button {
                    if !item.url.isEmpty {
                        appState.openRawLink(item.url, title: item.title, transitionID: sourceID)
                    }
                } label: {
                    VStack(spacing: 6) {
                        RemoteImageView(url: item.image, maxPixelSize: 160)
                            .frame(width: 44, height: 44)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func rankBadgeColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow.opacity(0.9)
        default: return .secondary
        }
    }
}

struct ImageTextSectionsView: View {
    let sections: [HomeSection]
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var deckPhase: CGFloat = 0
    @State private var dragProgress: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var lastDragEndedAt: Date = .distantPast
    @State private var transitionSeed = UUID().uuidString
    @State private var availableWidth: CGFloat = 360
    @State private var detectedRatios: [Int: CGFloat] = [:]

    private var currentNearestIndex: Int {
        let count = sections.count
        guard count > 0 else { return 0 }
        let rounded = Int((deckPhase + dragProgress).rounded())
        return ((rounded % count) + count) % count
    }

    private func cardSize(at index: Int, maxStageWidth: CGFloat) -> CGSize {
        let url = sections.indices.contains(index) ? sections[index].style : ""
        let rawRatio = detectedRatios[index]
            ?? MediaGridView.inferredAspectRatio(from: url)
            ?? 1.85
        let clamped = max(0.45, min(rawRatio, 2.8))
        let width = min(maxStageWidth, max(160, maxStageWidth))
        let height = min(420, max(110, width / clamped))
        let adjustedWidth = min(maxStageWidth, height * clamped)
        return CGSize(width: adjustedWidth, height: height)
    }

    private func updateDetectedRatio(index: Int, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let ratio = size.width / size.height
        if let existing = detectedRatios[index], abs(existing - ratio) < 0.01 { return }
        detectedRatios[index] = ratio
    }

    var body: some View {
        if sections.isEmpty {
            EmptyView()
        } else if sections.count == 1, let single = sections.first, !single.style.isEmpty {
            SingleImageLinkCardView(
                imageURL: single.style,
                title: single.title,
                subtitle: single.subtitle,
                targetURL: single.url
            )
        } else {
            let count = sections.count
            let visibleLayers = min(count, 3)
            let activeIdx = currentNearestIndex
            let leftInset: CGFloat = visibleLayers > 2 ? 24 : 12
            let rightInset: CGFloat = visibleLayers > 1 ? 24 : 12
            let bottomInset: CGFloat = visibleLayers > 1 ? 15 : 0
            let stageWidth = max(180, availableWidth - leftInset - rightInset)
            let activeCardSize = cardSize(at: activeIdx, maxStageWidth: stageWidth)
            let maxCardHeight = (0..<count).map { cardSize(at: $0, maxStageWidth: stageWidth).height }.max() ?? 176

            ZStack {
                OrbitalDeckStage(
                    phase: deckPhase + dragProgress,
                    count: count,
                    cardHeight: maxCardHeight
                ) { idx, isFront in
                    let section = sections[idx]
                    let tid = "section-\(transitionSeed)-\(idx)"
                    let itemSize = cardSize(at: idx, maxStageWidth: stageWidth)
                    Color(.secondarySystemGroupedBackground)
                        .frame(width: itemSize.width, height: itemSize.height)
                        .overlay {
                            RemoteImageView(url: section.style, maxPixelSize: 960, contentMode: .fit) { size in
                                updateDetectedRatio(index: idx, size: size)
                            }
                        }
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            if !section.title.isEmpty || !section.subtitle.isEmpty {
                                ZStack(alignment: .bottomLeading) {
                                    LinearGradient(
                                        colors: [.clear, .black.opacity(0.74)],
                                        startPoint: .center,
                                        endPoint: .bottom
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        if !section.title.isEmpty {
                                            Text(section.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(2)
                                        }
                                        if !section.subtitle.isEmpty {
                                            Text(section.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.86))
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .padding(.trailing, count > 1 ? 68 : 12)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.4)
                        }
                        .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 18)
                        .onTapGesture {
                            guard isFront,
                                  !isHorizontalDragging,
                                  abs(dragProgress) < 0.04,
                                  Date().timeIntervalSince(lastDragEndedAt) > 0.30,
                                  !section.url.isEmpty else { return }
                            appState.openRawLink(section.url, title: section.title, transitionID: tid)
                        }
                }
                .padding(.leading, leftInset)
                .padding(.trailing, rightInset)
                .padding(.bottom, bottomInset)

                if count > 1 {
                    HorizontalDeckPanOverlay(
                        isEnabled: count > 1,
                        activeCardSize: activeCardSize,
                        onTap: {
                            guard !isHorizontalDragging,
                                  abs(dragProgress) < 0.04,
                                  Date().timeIntervalSince(lastDragEndedAt) > 0.30,
                                  sections.indices.contains(activeIdx) else { return }
                            let section = sections[activeIdx]
                            if !section.url.isEmpty {
                                appState.openRawLink(section.url, title: section.title, transitionID: "section-\(transitionSeed)-\(activeIdx)")
                            }
                        },
                        onDragChanged: { dx in
                            if !isHorizontalDragging {
                                isHorizontalDragging = true
                            }
                            dragProgress = max(-1.15, min(1.15, -dx / 210.0))
                        },
                        onDragEnded: { dx, predicted, cancelled in
                            lastDragEndedAt = Date()
                            isHorizontalDragging = false
                            guard !cancelled else {
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
                    .frame(height: maxCardHeight)
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)
                    .padding(.bottom, bottomInset)

                    VStack {
                        HStack {
                            Spacer()
                            Text("\(activeIdx + 1)/\(count)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                                .foregroundStyle(.primary)
                        }
                        .allowsHitTesting(false)

                        Spacer()

                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Button {
                                    stepDeck(by: -1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    stepDeck(by: 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .frame(width: 22, height: 22)
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
                    .padding(10)
                    .frame(width: activeCardSize.width, height: activeCardSize.height)
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)
                    .padding(.bottom, bottomInset)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: visibleLayers > 1 ? maxCardHeight + bottomInset + 2 : maxCardHeight)
            .animation(.interpolatingSpring(stiffness: 220, damping: 24), value: maxCardHeight)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { _, newWidth in
                if newWidth > 80, abs(newWidth - availableWidth) > 2 {
                    availableWidth = newWidth
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func stepDeck(by delta: CGFloat) {
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 24)) {
            deckPhase = deckPhase.rounded() + delta
        }
    }
}

struct SectionHeaderRow: View {
    let title: String
    let subtitle: String
    let url: String
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !url.isEmpty {
                Button("更多") {
                    appState.openRawLink(url, title: title)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

struct LinkBarRowView: View {
    let sections: [HomeSection]
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(sections) { item in
                        Button {
                            let target = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !target.isEmpty {
                                appState.openRawLink(target, title: item.title)
                            } else if !item.title.isEmpty {
                                appState.openRawLink("/t/\(TopicItem.cleanTitle(item.title))", title: item.title)
                            }
                        } label: {
                            Text(item.title)
                                .font(.subheadline)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .contentShape(Capsule())
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
    }
}

struct GoodsStripView: View {
    let items: [PearGoods]
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    Button {
                        let target = item.detailURL.isEmpty ? item.buyURL : item.detailURL
                        if let url = URL(string: target) {
                            appState.push(.web(url: url))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImageView(url: item.image, maxPixelSize: 300)
                                .frame(width: 132, height: 132)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                            if !item.price.isEmpty {
                                Text(item.price)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(width: 132, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
    }
}

struct LivesStripView: View {
    let items: [LiveTopic]
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(items) { live in
                    Button {
                        if !live.presenterUID.isEmpty {
                            appState.push(.user(uid: live.presenterUID))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImageView(url: live.cover, maxPixelSize: 420)
                                .frame(width: 200, height: 112)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(live.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            if !live.summary.isEmpty {
                                Text(live.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 200, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
    }
}

public struct ProductRowView: View {
    public let product: ProductItem
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(product: ProductItem) { self.product = product }

    public var body: some View {
        Button {
            appState.cacheProductDetail(product)
            appState.push(.product(id: product.id, initialTitle: product.title, transitionID: "product-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: product.logo, maxPixelSize: 160)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(product.subtitle.isEmpty ? "\(Formatting.count(product.followNum)) 关注" : product.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !product.score.isEmpty {
                    Text(product.score)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "product-\(transitionSeed)", in: zoomNamespace, cornerRadius: 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct TopicRowView: View {
    public let topic: TopicItem
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(topic: TopicItem) { self.topic = topic }

    public var body: some View {
        Button {
            appState.cacheTopicDetail(topic)
            appState.push(.topic(tag: topic.title, transitionID: "topic-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: topic.logo, maxPixelSize: 144)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(TopicItem.cleanTitle(topic.title))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    let statsText: String = {
                        let primary = topic.feedNum > 0
                            ? "\(Formatting.count(topic.feedNum)) 讨论"
                            : (!topic.feedNumText.isEmpty
                                ? "\(topic.feedNumText) 讨论"
                                : (!topic.hotNumText.isEmpty ? "\(topic.hotNumText) 热度" : "\(Formatting.count(topic.hotNum)) 热度"))
                        return "\(primary) · \(Formatting.count(topic.followNum)) 关注"
                    }()
                    let subtitle = topic.description.isEmpty ? statsText : topic.description
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "topic-\(transitionSeed)", in: zoomNamespace, cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }
}

public struct UserRowView: View {
    public let user: UserBrief
    public var originBadgeIsCloud: Bool? = nil
    public var showBothOriginBadges: Bool = false
    public var contextDeleteTitle: String? = nil
    public var onContextDelete: (() -> Void)? = nil
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(
        user: UserBrief,
        originBadgeIsCloud: Bool? = nil,
        showBothOriginBadges: Bool = false,
        contextDeleteTitle: String? = nil,
        onContextDelete: (() -> Void)? = nil
    ) {
        self.user = user
        self.originBadgeIsCloud = originBadgeIsCloud
        self.showBothOriginBadges = showBothOriginBadges
        self.contextDeleteTitle = contextDeleteTitle
        self.onContextDelete = onContextDelete
    }

    public var body: some View {
        Button {
            appState.push(.user(
                uid: user.id,
                initialUsername: user.username,
                initialAvatar: user.avatar,
                transitionID: "userrow-\(transitionSeed)"
            ))
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: user.avatar, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(user.username)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if user.level > 0 {
                            Text("Lv.\(user.level)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    let desc = user.bio.isEmpty
                        ? "\(Formatting.count(user.fansNum)) 粉丝 · \(Formatting.count(user.feedNum)) 动态"
                        : user.bio
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if showBothOriginBadges {
                    HStack(spacing: 4) {
                        SourceOriginBadge(isCloud: false)
                        SourceOriginBadge(isCloud: true)
                    }
                } else if let originBadgeIsCloud {
                    SourceOriginBadge(isCloud: originBadgeIsCloud)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
            .modifier(OptionalDestructiveContextMenu(title: contextDeleteTitle, action: onContextDelete))
            .applyZoomSource(id: "userrow-\(transitionSeed)", in: zoomNamespace, cornerRadius: 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct AppRowView: View {
    public let app: AppItem
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(app: AppItem) { self.app = app }

    public var body: some View {
        Button {
            appState.cacheAppDetail(app)
            appState.push(.app(id: app.id, initialTitle: app.title, transitionID: "app-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: app.logo, maxPixelSize: 160)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let info = [app.version, app.size, app.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !app.score.isEmpty {
                    Label(app.score, systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "app-\(transitionSeed)", in: zoomNamespace, cornerRadius: 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct BrowseRowView: View {
    public let item: BrowseItem
    @Environment(AppState.self) private var appState

    public init(item: BrowseItem) { self.item = item }

    public var body: some View {
        Button {
            if !item.url.isEmpty { appState.openRawLink(item.url, title: item.title) }
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: item.logo, maxPixelSize: 132)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    let sub = [item.kindTitle, Formatting.relativeTime(item.dateline)].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(sub.isEmpty ? item.subtitle : sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

public struct CollectionCoverView: View {
    public let logoURL: String
    public var hasLocal: Bool = false
    public var hasCloud: Bool = true
    public var size: CGFloat = 46
    public var cornerRadius: CGFloat = 12

    public init(
        logoURL: String,
        hasLocal: Bool = false,
        hasCloud: Bool = true,
        size: CGFloat = 46,
        cornerRadius: CGFloat = 12
    ) {
        self.logoURL = coolapkNormalizedURL(logoURL.trimmingCharacters(in: .whitespacesAndNewlines))
        self.hasLocal = hasLocal
        self.hasCloud = hasCloud
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public static func fallbackSymbol(hasLocal: Bool, hasCloud: Bool) -> String {
        if hasCloud && hasLocal {
            return "folder.fill.badge.person.crop"
        } else if hasCloud {
            return "icloud.fill"
        } else {
            return "bookmark.fill"
        }
    }

    public static func fallbackTint(hasCloud: Bool) -> Color {
        hasCloud ? .blue : .accentColor
    }

    public var body: some View {
        let tint = Self.fallbackTint(hasCloud: hasCloud)
        let symbol = Self.fallbackSymbol(hasLocal: hasLocal, hasCloud: hasCloud)
        Group {
            if !logoURL.isEmpty {
                RemoteImageView(url: logoURL, maxPixelSize: 180, contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: max(14, size * 0.40), weight: .semibold))
                            .foregroundStyle(tint)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

public struct CollectionRowView: View {
    public let item: CollectionItem
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(item: CollectionItem) { self.item = item }

    private var resolvedLogoURL: String {
        if !item.logo.isEmpty { return item.logo }
        if let cached = appState.cachedCollectionDetail(id: item.id)?.logo, !cached.isEmpty {
            return cached
        }
        if let cloudCached = appState.historyAndFav.cachedCloudCollections.first(where: { $0.id == item.id })?.logo, !cloudCached.isEmpty {
            return cloudCached
        }
        return ""
    }

    private var hasMatchingLocalFolder: Bool {
        let norm = HistoryAndFavStore.normalizedFolderTitle(item.title)
        guard !norm.isEmpty else { return false }
        return appState.historyAndFav.folders.contains {
            !$0.isCloudLinked && HistoryAndFavStore.normalizedFolderTitle($0.title) == norm
        }
    }

    public var body: some View {
        Button {
            appState.cacheCollectionDetail(item)
            appState.push(.collection(id: item.id, initialTitle: item.title, transitionID: "col-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                CollectionCoverView(
                    logoURL: resolvedLogoURL,
                    hasLocal: hasMatchingLocalFolder,
                    hasCloud: true,
                    size: 46,
                    cornerRadius: 12
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(item.itemNum) 项内容 · \(Formatting.count(item.followNum)) 关注")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "col-\(transitionSeed)", in: zoomNamespace, cornerRadius: 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct EventRowView: View {
    public let event: EventItem
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(event: EventItem) { self.event = event }

    public var body: some View {
        Button {
            if !event.id.isEmpty, event.url.contains("/event/") || !event.url.hasPrefix("http") {
                appState.push(.event(id: event.id, initial: event, transitionID: "event-\(transitionSeed)"))
            } else if !event.url.isEmpty {
                appState.openRawLink(event.url, title: event.title, transitionID: "event-\(transitionSeed)")
            } else if !event.id.isEmpty {
                appState.push(.event(id: event.id, initial: event, transitionID: "event-\(transitionSeed)"))
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if !event.cover.isEmpty {
                    Color.clear
                        .frame(height: 168)
                        .overlay {
                            RemoteImageView(url: event.cover, maxPixelSize: 960)
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !event.title.isEmpty {
                            Text(event.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if !event.statusText.isEmpty {
                            Text(event.statusText)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    if !event.description.isEmpty {
                        Text(FeedHTMLParser.plainText(event.description))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    let meta = [
                        event.startTimeText,
                        event.joinNum > 0 ? "\(Formatting.count(event.joinNum)) 人参与" : ""
                    ].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "event-\(transitionSeed)", in: zoomNamespace, cornerRadius: 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct DyhRowView: View {
    public let dyh: DyhItem

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(dyh: DyhItem) {
        self.dyh = dyh
    }

    public var body: some View {
        let tid = "dyh-\(transitionSeed)"
        Button {
            appState.cacheDyhDetail(dyh)
            appState.push(.dyh(id: dyh.id, initialTitle: dyh.title, transitionID: tid))
        } label: {
            HStack(spacing: 12) {
                if !dyh.logo.isEmpty {
                    RemoteImageView(url: dyh.logo, maxPixelSize: 220)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "newspaper")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(dyh.title.isEmpty ? "看看号" : dyh.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !dyh.description.isEmpty {
                        Text(FeedHTMLParser.plainText(dyh.description))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    let meta = [
                        dyh.username.isEmpty ? "" : "@\(dyh.username)",
                        dyh.followNum > 0 ? "\(Formatting.count(dyh.followNum)) 关注" : ""
                    ].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: tid, in: zoomNamespace, cornerRadius: 20)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
}

public struct GoodsRankingCardView: View {
    public let item: GoodsRankingItem
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(item: GoodsRankingItem) {
        self.item = item
    }

    public var body: some View {
        let sourceID = "goodsranking-\(transitionSeed)-\(item.id)"
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openRanking(transitionID: sourceID)
            } label: {
                HStack(spacing: 12) {
                    if !item.cover.isEmpty {
                        RemoteImageView(url: item.cover, maxPixelSize: 160)
                            .frame(width: 48, height: 48)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.16))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "crown.fill")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                            }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("好物榜")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.16), in: Capsule())
                                .foregroundStyle(.orange)
                            Text(item.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        if !item.statsText.isEmpty {
                            Text(item.statsText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if !item.dateText.isEmpty {
                        Text(item.dateText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            let topProducts = Array(item.products.prefix(3))
            if !topProducts.isEmpty {
                let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(3, max(1, topProducts.count)))
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(topProducts) { prod in
                        let prodSourceID = "goodsprod-\(transitionSeed)-\(prod.id)"
                        Button {
                            if !prod.url.isEmpty {
                                appState.openRawLink(prod.url, title: prod.title, transitionID: prodSourceID)
                            } else {
                                openRanking(transitionID: prodSourceID)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topLeading) {
                                    RemoteImageView(url: prod.cover, maxPixelSize: 220, contentMode: .fit)
                                        .frame(height: 76)
                                        .frame(maxWidth: .infinity)
                                        .padding(6)
                                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Text("TOP \(prod.rank)")
                                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(prod.rank == 1 ? Color.red : (prod.rank == 2 ? Color.orange : Color.brown), in: Capsule())
                                        .padding(5)
                                }

                                Text(prod.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                if !prod.priceText.isEmpty {
                                    Text(prod.priceText)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .applyZoomSource(id: prodSourceID, in: zoomNamespace, cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .c001CardStyle(cornerRadius: 20)
        .applyZoomSource(id: sourceID, in: zoomNamespace, cornerRadius: 20)
        .padding(.horizontal, 12)
    }

    private func openRanking(transitionID: String) {
        if !item.url.isEmpty {
            appState.openRawLink(item.url, title: item.title, transitionID: transitionID)
        } else if item.id.allSatisfy(\.isNumber) {
            appState.push(.feed(id: item.id, transitionID: transitionID))
        }
    }
}
