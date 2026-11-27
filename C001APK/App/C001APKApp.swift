import CoolapkKit
import SwiftUI
import UIKit

@main
struct C001APKApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()
    @State private var backgroundEnteredAt: Date?

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appState)
                .tint(appState.settings.accentColor)
                .preferredColorScheme(appState.settings.appearanceMode.colorScheme)
                .task {
                    await appState.bootstrap()
                    appState.checkClipboardForCoolapkLink()
                }
                .onOpenURL { url in
                    appState.handleIncomingOpenURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        backgroundEnteredAt = Date()
                    case .active:
                        backgroundEnteredAt = nil
                        appState.checkClipboardForCoolapkLink()
                        Task {
                            await CoolapkClient.shared.prepareForForeground(flushConnections: false)
                        }
                    default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    RichTextRenderer.purgeCache()
                    EmojiBundleStore.purgeCache()
                    Task { await ImagePipeline.shared.purgeMemory() }
                }
        }
    }
}
