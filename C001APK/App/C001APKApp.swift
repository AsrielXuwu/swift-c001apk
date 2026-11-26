import SwiftUI
import UIKit

@main
struct C001APKApp: App {
    @State private var appState = AppState()

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
