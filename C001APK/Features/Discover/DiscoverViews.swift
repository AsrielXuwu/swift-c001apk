import CoolapkKit
import SwiftUI
import UIKit
import WebKit

// MARK: - Topic Detail

public struct TopicDetailView: View {
    public let tag: String

    @Environment(AppState.self) private var appState
    @State private var topic: TopicItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var listType = "lastupdate_desc"
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false

    public init(tag: String) { self.tag = tag }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let topic {
                    HStack(spacing: 12) {
                        RemoteImageView(url: topic.logo, maxPixelSize: 180)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("#\(topic.title)#").font(.headline)
                            Text("\(Formatting.count(topic.feedNum)) 动态 · \(Formatting.count(topic.followNum)) 关注")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !topic.description.isEmpty {
                                Text(topic.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Button(topic.isFollowed ? "已关注" : "关注") {
                            Task { await toggleFollow(topic) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(topic.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(topic.isFollowed ? Color.primary : Color.accentColor)
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 16)
                    .padding(.horizontal, 12)
                }

                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach([
                            ("lastupdate_desc", "最新回复"),
                            ("dateline_desc", "最新发布"),
                            ("popular", "热门")
                        ], id: \.0) { value, label in
                            let isSelected = listType == value
                            Button {
                                withAnimation(.snappy(duration: 0.22)) {
                                    listType = value
                                }
                            } label: {
                                Text(label)
                                    .font(.caption.weight(isSelected ? .semibold : .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .padding(.horizontal, 14)
                .onChange(of: listType) { _, _ in
                    Task { await reloadFeeds() }
                }

                if isLoading && rows.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        HomeRowRenderer(row: row)
                            .onAppear {
                                if idx >= rows.count - 4 { Task { await loadMore() } }
                            }
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("#\(tag)#")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            topic = try? await API.topicDetail(tag: tag)
            await reloadFeeds()
        }
    }

    private func reloadFeeds() async {
        isLoading = true
        defer { isLoading = false }
        page = 1
        do {
            rows = try await API.topicFeeds(tag: tag, page: 1, listType: listType)
            hasMore = !rows.isEmpty
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let next = page + 1
        if let fetched = try? await API.topicFeeds(tag: tag, page: next, listType: listType) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }

    private func toggleFollow(_ current: TopicItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        let next = !current.isFollowed
        do {
            try await API.followTopic(tag: tag, follow: next)
            topic?.isFollowed = next
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - Product Detail

public struct ProductDetailView: View {
    public let productID: String

    @Environment(AppState.self) private var appState
    @State private var product: ProductItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var page = 1
    @State private var hasMore = true

    public init(productID: String) { self.productID = productID }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let product {
                    HStack(spacing: 12) {
                        RemoteImageView(url: product.logo, maxPixelSize: 180)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.title).font(.headline)
                            Text("评分 \(product.score.isEmpty ? "-" : product.score) · \(Formatting.count(product.followNum)) 关注")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(product.isFollowed ? "已关注" : "关注") {
                            Task { await toggleFollow(product) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(product.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(product.isFollowed ? Color.primary : Color.accentColor)
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 16)
                    .padding(.horizontal, 12)
                }

                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    HomeRowRenderer(row: row)
                        .onAppear {
                            if idx >= rows.count - 4 { Task { await loadMore() } }
                        }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(product?.title ?? "数码产品")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            product = try? await API.productDetail(id: productID)
            let link = (product?.url.isEmpty == false ? product!.url : "#/feed/productFeedList?id=\(productID)")
            rows = (try? await API.productFeed(pageLink: link, page: 1)) ?? []
            hasMore = !rows.isEmpty
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        let link = (product?.url.isEmpty == false ? product!.url : "#/feed/productFeedList?id=\(productID)")
        let next = page + 1
        if let fetched = try? await API.productFeed(pageLink: link, page: next) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }

    private func toggleFollow(_ current: ProductItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        let next = !current.isFollowed
        do {
            try await API.followProduct(id: current.id, follow: next)
            product?.isFollowed = next
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - App Detail

public struct AppDetailView: View {
    public let appID: String

    @Environment(AppState.self) private var appState
    @Environment(\.zoomNamespace) private var zoomNamespace
    @State private var transitionSeed = UUID().uuidString
    @State private var app: AppItem?
    @State private var comments: [HomeFeedRow] = []
    @State private var page = 1
    @State private var hasMore = true

    public init(appID: String) { self.appID = appID }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let app {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            RemoteImageView(url: app.logo, maxPixelSize: 200)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.title).font(.title3.weight(.semibold))
                                Text("\(app.version) · \(app.size) · \(app.developer)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !app.score.isEmpty {
                                    Label("\(app.score) 分", systemImage: "star.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        if !app.screenshots.isEmpty {
                            let shotPrefix = "appshots-\(transitionSeed)"
                            let shotMedia = app.screenshots.map { FeedMedia(sourceUrl: $0) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(app.screenshots.enumerated()), id: \.offset) { idx, url in
                                        Button {
                                            appState.openMedia(shotMedia, at: idx, sourcePrefix: shotPrefix)
                                        } label: {
                                            RemoteImageView(url: url, maxPixelSize: 540)
                                                .frame(width: 140, height: 240)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .applyZoomSource(id: "\(shotPrefix)-\(idx)", in: zoomNamespace)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if !app.description.isEmpty {
                            Text(FeedHTMLParser.plainText(app.description))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 16)
                    .padding(.horizontal, 12)
                }

                ForEach(Array(comments.enumerated()), id: \.element.id) { idx, row in
                    HomeRowRenderer(row: row)
                        .onAppear {
                            if idx >= comments.count - 4 { Task { await loadMore() } }
                        }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(app?.title ?? "应用详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            app = try? await API.appDetail(id: appID)
            comments = (try? await API.appComments(id: appID, page: 1)) ?? []
            hasMore = !comments.isEmpty
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        let next = page + 1
        if let fetched = try? await API.appComments(id: appID, page: next) {
            var seen = Set(comments.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            comments.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }
}

// MARK: - Dyh (看看号)

public struct DyhDetailView: View {
    public let dyhID: String

    @Environment(AppState.self) private var appState
    @State private var dyh: DyhItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var page = 1
    @State private var hasMore = true

    public init(dyhID: String) { self.dyhID = dyhID }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let dyh {
                    HStack(spacing: 12) {
                        RemoteImageView(url: dyh.logo, maxPixelSize: 180)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dyh.title).font(.headline)
                            Text(dyh.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button(dyh.isFollowed ? "已订阅" : "订阅") {
                            Task { await toggleFollow(dyh) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(dyh.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(dyh.isFollowed ? Color.primary : Color.accentColor)
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 16)
                    .padding(.horizontal, 12)
                }

                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    HomeRowRenderer(row: row)
                        .onAppear {
                            if idx >= rows.count - 4 { Task { await loadMore() } }
                        }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(dyh?.title ?? "看看号")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            dyh = try? await API.dyhDetail(id: dyhID)
            rows = (try? await API.dyhArticles(id: dyhID, page: 1)) ?? []
            hasMore = !rows.isEmpty
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        let next = page + 1
        if let fetched = try? await API.dyhArticles(id: dyhID, page: next) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }

    private func toggleFollow(_ current: DyhItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        let next = !current.isFollowed
        do {
            try await API.followDyh(id: dyhID, follow: next)
            dyh?.isFollowed = next
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - Collection (收藏夹)

public struct CollectionDetailView: View {
    public let collectionID: String

    @Environment(AppState.self) private var appState
    @State private var collection: CollectionItem?
    @State private var rows: [HomeFeedRow] = []
    @State private var page = 1
    @State private var hasMore = true

    public init(collectionID: String) { self.collectionID = collectionID }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let collection {
                    HStack(spacing: 12) {
                        RemoteImageView(url: collection.logo, maxPixelSize: 180)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collection.title).font(.headline)
                            Text("\(collection.itemNum) 项 · \(Formatting.count(collection.followNum)) 关注")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(collection.isFollowed ? "已关注" : "关注") {
                            Task { await toggleFollow(collection) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(collection.isFollowed ? Color.clear : Color.accentColor.opacity(0.18), in: Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .foregroundStyle(collection.isFollowed ? Color.primary : Color.accentColor)
                    }
                    .padding(14)
                    .c001CardStyle(cornerRadius: 16)
                    .padding(.horizontal, 12)
                }

                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    HomeRowRenderer(row: row)
                        .onAppear {
                            if idx >= rows.count - 4 { Task { await loadMore() } }
                        }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(collection?.title ?? "收藏夹")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            collection = try? await API.collectionDetail(id: collectionID)
            rows = (try? await API.collectionItems(id: collectionID, page: 1)) ?? []
            hasMore = !rows.isEmpty
        }
    }

    private func loadMore() async {
        guard hasMore else { return }
        let next = page + 1
        if let fetched = try? await API.collectionItems(id: collectionID, page: next) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }

    private func toggleFollow(_ current: CollectionItem) async {
        guard appState.accounts.isLoggedIn else { appState.showLoginSheet = true; return }
        let next = !current.isFollowed
        do {
            try await API.followCollection(id: collectionID, follow: next)
            collection?.isFollowed = next
        } catch {
            _ = await appState.handleAPIError(error)
        }
    }
}

// MARK: - Event Detail

public struct EventDetailView: View {
    public let eventID: String
    @State private var event: EventItem?
    @State private var isLoading = false

    public init(eventID: String) { self.eventID = eventID }

    public var body: some View {
        ScrollView {
            if isLoading && event == nil {
                ProgressView().padding(.vertical, 60)
            } else if let event {
                VStack(alignment: .leading, spacing: 14) {
                    if !event.cover.isEmpty {
                        RemoteImageView(url: event.cover, maxPixelSize: 1200)
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text(event.title).font(.title3.weight(.bold))
                    if !event.startTimeText.isEmpty {
                        Text(event.startTimeText).font(.caption).foregroundStyle(.secondary)
                    }
                    if !event.description.isEmpty {
                        Text(FeedHTMLParser.plainText(event.description)).font(.body)
                    }
                }
                .padding(16)
            } else {
                ContentUnavailableView("活动不可用", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(event?.title ?? "活动")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            event = try? await API.eventDetail(id: eventID)
            isLoading = false
        }
    }
}

// MARK: - Generic Page / CoolPic / InAppWebView

public struct PageFeedView: View {
    public let link: String
    public let title: String

    @Environment(AppState.self) private var appState
    @State private var rows: [HomeFeedRow] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false

    public init(link: String, title: String) {
        self.link = link
        self.title = title
    }

    public var body: some View {
        ScrollView {
            if isLoading && rows.isEmpty {
                ProgressView().padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        HomeRowRenderer(row: row)
                            .onAppear {
                                if idx >= rows.count - 4 { Task { await loadMore() } }
                            }
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                if link == "/main/headline" {
                    rows = try await API.headlineFeed(page: 1)
                } else {
                    rows = try await API.linkFeed(link: link, page: 1)
                }
                hasMore = !rows.isEmpty
            } catch {
                _ = await appState.handleAPIError(error)
            }
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let next = page + 1
        let fetched: [HomeFeedRow]?
        if link == "/main/headline" {
            fetched = try? await API.headlineFeed(page: next)
        } else {
            fetched = try? await API.linkFeed(link: link, page: next)
        }
        if let fetched {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }
}

public struct CoolPicView: View {
    public let initialTag: String

    @State private var rows: [HomeFeedRow] = []
    @State private var sortType = "recommend"
    @State private var page = 1
    @State private var hasMore = true

    public init(initialTag: String = "全部") { self.initialTag = initialTag }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    HomeRowRenderer(row: row)
                        .onAppear {
                            if idx >= rows.count - 4 { Task { await loadMore() } }
                        }
                }
            }
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach([
                        ("recommend", "推荐"),
                        ("new", "最新"),
                        ("hot", "最热")
                    ], id: \.0) { value, label in
                        let isSelected = sortType == value
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                sortType = value
                            }
                        } label: {
                            Text(label)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .onChange(of: sortType) { _, _ in
                Task { await reload() }
            }
        }
        .navigationTitle("酷图")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        page = 1
        rows = (try? await API.coolPic(tag: initialTag, type: sortType, page: 1)) ?? []
        hasMore = !rows.isEmpty
    }

    private func loadMore() async {
        guard hasMore else { return }
        let next = page + 1
        if let fetched = try? await API.coolPic(tag: initialTag, type: sortType, page: next) {
            var seen = Set(rows.map(\.id))
            let unique = fetched.filter { seen.insert($0.id).inserted }
            rows.append(contentsOf: unique)
            hasMore = !unique.isEmpty
            if hasMore { page = next }
        }
    }
}

public struct InAppWebView: View {
    public let url: URL

    public init(url: URL) { self.url = url }

    public var body: some View {
        WebViewRepresentable(url: url)
            .navigationTitle(url.host ?? "网页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url)
                }
            }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
