import CoolapkKit
import Foundation
import Observation

@MainActor
@Observable
public final class HomeFeedViewModel {
    public private(set) var rowsByTab: [HomeTabType: [HomeFeedRow]] = [:]
    public private(set) var subCategoriesByTab: [HomeTabType: [HomeSection]] = [:]
    public private(set) var selectedSubCategoryByTab: [HomeTabType: HomeSection] = [:]
    public private(set) var loadingTabs: Set<HomeTabType> = []
    public private(set) var loadingMoreTabs: Set<HomeTabType> = []
    public private(set) var hasMoreByTab: [HomeTabType: Bool] = [:]
    public private(set) var errorByTab: [HomeTabType: String] = [:]

    private var pageByTab: [HomeTabType: Int] = [:]
    private var sessionMarker = -1

    public init() {}

    public func syncSessionIfNeeded(appState: AppState) {
        if sessionMarker != appState.sessionVersion {
            sessionMarker = appState.sessionVersion
            rowsByTab.removeAll()
            subCategoriesByTab.removeAll()
            selectedSubCategoryByTab.removeAll()
            loadingTabs.removeAll()
            loadingMoreTabs.removeAll()
            hasMoreByTab.removeAll()
            errorByTab.removeAll()
            pageByTab.removeAll()
        }
    }

    public func selectSubCategory(_ section: HomeSection, for tab: HomeTabType, appState: AppState) async {
        selectedSubCategoryByTab[tab] = section
        rowsByTab[tab] = []
        await loadInitial(tab: tab, appState: appState, force: true)
    }

    public func loadInitial(tab: HomeTabType, appState: AppState, force: Bool = false) async {
        syncSessionIfNeeded(appState: appState)
        if !force, let existing = rowsByTab[tab], !existing.isEmpty { return }
        guard !loadingTabs.contains(tab) else { return }

        loadingTabs.insert(tab)
        errorByTab[tab] = nil
        pageByTab[tab] = 1
        hasMoreByTab[tab] = true

        let expectedSession = appState.sessionVersion
        await fetch(tab: tab, page: 1, append: false, appState: appState, expectedSession: expectedSession)
        loadingTabs.remove(tab)
    }

    public func loadMore(tab: HomeTabType, appState: AppState) async {
        guard !loadingTabs.contains(tab),
              !loadingMoreTabs.contains(tab),
              hasMoreByTab[tab] != false else { return }

        loadingMoreTabs.insert(tab)
        let nextPage = (pageByTab[tab] ?? 1) + 1
        let expectedSession = appState.sessionVersion
        await fetch(tab: tab, page: nextPage, append: true, appState: appState, expectedSession: expectedSession)
        loadingMoreTabs.remove(tab)
    }

    private func fetch(tab: HomeTabType, page: Int, append: Bool, appState: AppState, expectedSession: Int) async {
        do {
            let loaded: [HomeFeedRow]
            switch tab {
            case .feed:
                loaded = try await API.homeFeed(page: page)
            case .hot:
                loaded = try await API.pageFeed(pageName: "V9_HOME_TAB_RANKING", page: page)
            case .topic:
                if subCategoriesByTab[.topic]?.isEmpty != false {
                    let categories = try await API.topicVerticalTabs()
                    subCategoriesByTab[.topic] = categories
                    if selectedSubCategoryByTab[.topic] == nil {
                        selectedSubCategoryByTab[.topic] = categories.count > 1 ? categories[1] : categories.first
                    }
                }
                if let sub = selectedSubCategoryByTab[.topic], !sub.url.isEmpty {
                    loaded = try await API.linkFeed(link: sub.url, page: page)
                } else {
                    loaded = try await API.pageFeed(pageName: "V11_VERTICAL_TOPIC", page: page)
                }
            case .product:
                if subCategoriesByTab[.product]?.isEmpty != false {
                    let categories = try await API.productCategoryTabs()
                    subCategoriesByTab[.product] = categories
                    if selectedSubCategoryByTab[.product] == nil {
                        selectedSubCategoryByTab[.product] = categories.first
                    }
                }
                if let sub = selectedSubCategoryByTab[.product], !sub.url.isEmpty {
                    loaded = try await API.linkFeed(link: sub.url, page: page)
                } else {
                    let json = try await CoolapkClient.shared.get("/v6/product/categoryList", ["page": String(page)])
                    loaded = API.rows(from: json.data.array)
                }
            case .coolpic:
                loaded = try await API.pageFeed(pageName: "V11_FIND_COOLPIC", page: page)
            case .app:
                loaded = try await API.appIndex(type: 1, page: page)
            case .follow:
                loaded = try await API.pageFeed(pageName: API.followPageName, page: page)
            case .none:
                loaded = []
            }

            guard expectedSession == appState.sessionVersion else { return }
            if append {
                let current = rowsByTab[tab] ?? []
                var seen = Set(current.map(\.id))
                let unique = loaded.filter { seen.insert($0.id).inserted }
                rowsByTab[tab] = current + unique
                if unique.isEmpty {
                    hasMoreByTab[tab] = false
                } else {
                    pageByTab[tab] = page
                }
            } else {
                rowsByTab[tab] = loaded
                hasMoreByTab[tab] = !loaded.isEmpty
                pageByTab[tab] = page
            }
        } catch {
            guard expectedSession == appState.sessionVersion else { return }
            let retried = await appState.handleAPIError(error)
            if retried && !append {
                await fetch(tab: tab, page: page, append: false, appState: appState, expectedSession: expectedSession)
                return
            }
            if !append {
                errorByTab[tab] = error.localizedDescription
            }
        }
    }
}
