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
        let schema = Schema([
            Exercise.self,
            Template.self,
            WorkoutSession.self,
            WorkoutSet.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
