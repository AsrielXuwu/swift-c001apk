import SwiftUI
import UIKit

@main
struct C001APKApp: App {
    @State private var appState = AppState()

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        appearance.shadowColor = .clear

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance = appearance
        navBar.compactScrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appState)
                .tint(appState.settings.accentColor)
                .preferredColorScheme(appState.settings.appearanceMode.colorScheme)
                .task {
                    await appState.bootstrap()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    RichTextRenderer.purgeCache()
                    Task { await ImagePipeline.shared.purgeMemory() }
                }
        }
    }
}
