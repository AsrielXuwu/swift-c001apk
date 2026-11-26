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

    private func cardSize(at index: Int, maxStageWidth: CGFloat) -> CGSize {
        let url = banners.indices.contains(index) ? banners[index].image : ""
        let rawRatio = detectedRatios[index]
            ?? MediaGridView.inferredAspectRatio(from: url)
            ?? 1.85
        let clamped = max(0.55, min(rawRatio, 2.8))
        let naturalH = maxStageWidth / clamped
        let finalH = min(320, max(130, naturalH))
        let finalW = min(maxStageWidth, max(160, finalH * clamped))
        return CGSize(width: finalW, height: finalH)
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
                            RemoteImageView(url: banner.image, maxPixelSize: 1080, contentMode: .fill) { size in
                                updateDetectedRatio(index: idx, size: size)
                            }
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

struct IconLinksScrollView: View {
    let links: [HomeIconLink]
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(links) { link in
                    Button {
                        if !link.url.isEmpty { appState.openRawLink(link.url, title: link.title) }
                    } label: {
                        VStack(spacing: 6) {
                            RemoteImageView(url: link.image, maxPixelSize: 132)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(link.title)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(width: 58)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
        let clamped = max(0.55, min(rawRatio, 2.8))
        let naturalH = maxStageWidth / clamped
        let finalH = min(320, max(130, naturalH))
        let finalW = min(maxStageWidth, max(160, finalH * clamped))
        return CGSize(width: finalW, height: finalH)
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
                            RemoteImageView(url: section.style, maxPixelSize: 960, contentMode: .fill) { size in
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
                            if !item.url.isEmpty { appState.openRawLink(item.url, title: item.title) }
                        } label: {
                            Text(item.title)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
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
            appState.push(.product(id: product.id, transitionID: "product-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: product.logo, maxPixelSize: 160)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "product-\(transitionSeed)", in: zoomNamespace)
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
            appState.push(.topic(tag: topic.title, transitionID: "topic-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: topic.logo, maxPixelSize: 144)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(user: UserBrief) { self.user = user }

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
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "userrow-\(transitionSeed)", in: zoomNamespace)
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
            appState.push(.app(id: app.id, transitionID: "app-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: app.logo, maxPixelSize: 160)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "app-\(transitionSeed)", in: zoomNamespace)
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

public struct CollectionRowView: View {
    public let item: CollectionItem
    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString

    public init(item: CollectionItem) { self.item = item }

    public var body: some View {
        Button {
            appState.push(.collection(id: item.id, transitionID: "col-\(transitionSeed)"))
        } label: {
            HStack(spacing: 12) {
                RemoteImageView(url: item.logo, maxPixelSize: 144)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
            }
            .padding(14)
            .c001CardStyle(cornerRadius: 20)
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "col-\(transitionSeed)", in: zoomNamespace)
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
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: "event-\(transitionSeed)", in: zoomNamespace)
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
            appState.push(.dyh(id: dyh.id, transitionID: tid))
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
            .padding(.horizontal, 12)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .applyZoomSource(id: tid, in: zoomNamespace)
        }
        .buttonStyle(.plain)
    }
}
