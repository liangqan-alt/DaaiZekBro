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

    var sharedModelContainer: ModelContainer = {
        do {
            return try DaaiZekBroSchema.makeModelContainer(
                isStoredInMemoryOnly: AppLaunchConfiguration.isUITesting
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(notificationRouter: notificationRouter)
                .tint(DZColor.pump500)
                .onAppear {
                    appDelegate.notificationRouter = notificationRouter
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
