//
//  DaaiZekBroApp.swift
//  DaaiZekBro
//
//  Created by liangqan on 2026/5/20.
//

import SwiftUI
import SwiftData

@main
struct DaaiZekBroApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @StateObject private var notificationRouter = NotificationNavigationRouter()
    private let modelContainerResult = AppModelContainerLoader.live().load()

    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch modelContainerResult {
        case .success(let container):
            ContentView(notificationRouter: notificationRouter)
                .tint(DZColor.pump500)
                .onAppear {
                    appDelegate.notificationRouter = notificationRouter
                    PhoneWatchTrainingStateSync.shared.activate()
                }
                .modelContainer(container)
        case .failure(let failure):
            ModelContainerFailureView(failure: failure)
                .tint(DZColor.pump500)
        }
    }
}
