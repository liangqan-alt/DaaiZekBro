import SwiftUI

@main
struct DaaiZekBroWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView(sessionManager: sessionManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            sessionManager.refreshFromApplicationContext()
            sessionManager.requestTrainingState()
        }
    }
}
