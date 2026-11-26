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
    @State private var activeIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isHorizontalDragging = false
    @State private var lastDragEndedAt: Date = .distantPast

    var body: some View {
        if banners.isEmpty {
            EmptyView()
        } else {
            let count = banners.count
            let safeActive = ((activeIndex % count) + count) % count
            let visibleLayers = min(count, 3)

            ZStack {
                ForEach((0..<visibleLayers).reversed(), id: \.self) { depth in
                    let idx = (safeActive + depth) % count
                    let banner = banners[idx]
                    let isFront = (depth == 0)

                    bannerCard(banner: banner, index: idx, count: count, isFront: isFront)
                        .scaleEffect(scaleFor(depth: depth))
                        .rotationEffect(.degrees(rotationFor(depth: depth, isFront: isFront)))
                        .offset(x: xOffsetFor(depth: depth, isFront: isFront), y: yOffsetFor(depth: depth))
                        .opacity(depth == 2 ? 0.90 : (depth == 1 ? 0.96 : 1.0))
                        .zIndex(Double(visibleLayers - depth))
                        .allowsHitTesting(isFront)
                }
            }
            .padding(.leading, visibleLayers > 2 ? 26 : 14)
            .padding(.trailing, visibleLayers > 1 ? 26 : 14)
            .padding(.bottom, visibleLayers > 1 ? 16 : 0)
            .frame(height: visibleLayers > 1 ? 204 : 184)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard count > 1 else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if isHorizontalDragging || abs(dx) > max(12, abs(dy) * 1.15) {
                            isHorizontalDragging = true
                            dragOffset = dx
                        }
                    }
                    .onEnded { value in
                        guard count > 1 else { return }
                        let dx = value.translation.width
                        let predicted = value.predictedEndTranslation.width
                        let wasDragging = isHorizontalDragging || abs(dx) > 10
                        if wasDragging {
                            lastDragEndedAt = Date()
                        }
                        isHorizontalDragging = false
                        guard wasDragging else {
                            withAnimation(.snappy(duration: 0.22)) { dragOffset = 0 }
                            return
                        }
                        withAnimation(.snappy(duration: 0.28)) {
                            if dx < -42 || predicted < -90 {
                                activeIndex = (safeActive + 1) % count
                            } else if dx > 42 || predicted > 90 {
                                activeIndex = (safeActive - 1 + count) % count
                            }
                            dragOffset = 0
                        }
                    }
            )
            .padding(.vertical, 2)
        }
    }

    private func bannerCard(banner: HomeBanner, index: Int, count: Int, isFront: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .frame(height: 184)
                .overlay {
                    RemoteImageView(url: banner.image, maxPixelSize: 1080)
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if !banner.title.isEmpty || !banner.subtitle.isEmpty {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.70)],
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
                .overlay(alignment: .topTrailing) {
                    if isFront && count > 1 {
                        Text("\(index + 1)/\(count)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .foregroundStyle(.primary)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture {
                    guard isFront,
                          !isHorizontalDragging,
                          abs(dragOffset) < 4,
                          Date().timeIntervalSince(lastDragEndedAt) > 0.30,
                          !banner.url.isEmpty else { return }
                    appState.openRawLink(banner.url)
                }

            if isFront && count > 1 {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.snappy(duration: 0.26)) {
                            activeIndex = (index - 1 + count) % count
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy(duration: 0.26)) {
                            activeIndex = (index + 1) % count
                        }
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
                .padding(10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.systemBackground).opacity(isFront ? 0.92 : 0.80), lineWidth: 1.4)
        }
        .shadow(color: .black.opacity(isFront ? 0.14 : 0.08), radius: isFront ? 9 : 5, x: 0, y: 3)
    }

    private func scaleFor(depth: Int) -> CGFloat {
        let base: CGFloat = depth == 0 ? 1.0 : (depth == 1 ? 0.95 : 0.91)
        if depth > 0 {
            let progress = min(1, abs(dragOffset) / 140)
            return base + progress * 0.03
        }
        return base
    }

    private func rotationFor(depth: Int, isFront: Bool) -> Double {
        if isFront {
            return Double(dragOffset) / 22.0
        }
        return depth == 1 ? 4.0 : -4.0
    }

    private func xOffsetFor(depth: Int, isFront: Bool) -> CGFloat {
        if isFront {
            return dragOffset
        }
        return depth == 1 ? 14 : -12
    }

    private func yOffsetFor(depth: Int) -> CGFloat {
        depth == 0 ? 0 : (depth == 1 ? 8 : 15)
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
                        if !link.url.isEmpty { appState.openRawLink(link.url) }
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(sections) { section in
                    Button {
                        if !section.url.isEmpty { appState.openRawLink(section.url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RemoteImageView(url: section.style, maxPixelSize: 480)
                                .frame(width: 180, height: 100)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(section.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if !section.subtitle.isEmpty {
                                Text(section.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 180, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
                    appState.openRawLink(url)
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
                            if !item.url.isEmpty { appState.openRawLink(item.url) }
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
                    Text("#\(topic.title)#")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    let subtitle = topic.description.isEmpty
                        ? "\(Formatting.count(topic.feedNum)) 动态 · \(Formatting.count(topic.followNum)) 关注"
                        : topic.description
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
            .applyZoomSource(id: "topic-\(transitionSeed)", in: zoomNamespace)
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
            appState.push(.user(uid: user.id, transitionID: "userrow-\(transitionSeed)"))
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
            if !item.url.isEmpty { appState.openRawLink(item.url) }
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
