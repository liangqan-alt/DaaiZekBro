//
//  ContentView.swift
//  DaaiZekBro
//
//  Created by liangqan on 2026/5/20.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var notificationRouter: NotificationNavigationRouter
    @Environment(\.modelContext) private var modelContext
    @State private var path: [AppRoute] = []
    @State private var seedStatus: SeedStatus = .loading

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch seedStatus {
                case .loading:
                    ProgressView("正在准备模板...")
                case .ready:
                    TemplateListView(path: $path)
                case .failed(let errorMessage):
                    ContentUnavailableView(
                        "模板准备失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .currentWorkout(let sessionID):
                    CurrentWorkoutView(sessionID: sessionID, path: $path)
                case .exerciseLogging(let sessionID, let exerciseName):
                    ExerciseLoggingView(sessionID: sessionID, exerciseName: exerciseName)
                case .templateEdit(let templateID):
                    TemplateEditView(templateID: templateID)
                case .trainingSchedule:
                    TrainingScheduleView()
                case .settings:
                    SettingsView()
                }
            }
            .task {
                await writeSeedData()
            }
            .onChange(of: seedStatus) { _, _ in
                routePendingRestNotificationIfReady()
            }
            .onReceive(notificationRouter.$pendingRestNotification) { _ in
                routePendingRestNotificationIfReady()
            }
        }
    }

    @MainActor
    private func writeSeedData() async {
        do {
            #if DEBUG
            if let fixtureName = AppLaunchConfiguration.uiFixtureName {
                try UITestFixtures.write(
                    named: fixtureName,
                    now: AppLaunchConfiguration.now(),
                    in: modelContext
                )
                seedStatus = .ready
                return
            }
            #endif

            try SeedData.writeAndDedup(in: modelContext)
            seedStatus = .ready
        } catch {
            seedStatus = .failed(error.localizedDescription)
        }
    }

    private func routePendingRestNotificationIfReady() {
        guard seedStatus == .ready, let payload = notificationRouter.pendingRestNotification else {
            return
        }

        do {
            path = try NotificationNavigationResolver.route(for: payload, in: modelContext)
        } catch {
            path.removeAll()
        }

        notificationRouter.consume(payload)
    }
}

private enum SeedStatus: Equatable {
    case loading
    case ready
    case failed(String)
}

#Preview {
    ContentView(notificationRouter: NotificationNavigationRouter())
        .modelContainer(
            for: [
                Exercise.self,
                Template.self,
                TemplateExercise.self,
                WorkoutSession.self,
                TrainingCycle.self,
                TrainingCycleSlot.self,
                TrainingDayOverride.self,
                WorkoutSessionExerciseSnapshot.self,
                WorkoutSet.self,
            ],
            inMemory: true
        )
}
