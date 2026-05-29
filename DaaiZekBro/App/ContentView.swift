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
                case .exerciseLogging(let sessionID, let exerciseOrderIndex, let exerciseName):
                    ExerciseLoggingView(
                        sessionID: sessionID,
                        exerciseOrderIndex: exerciseOrderIndex,
                        exerciseName: exerciseName
                    )
                case .templateEdit(let templateID):
                    TemplateEditView(templateID: templateID)
                case .trainingSchedule:
                    TrainingScheduleView()
                case .workoutHistory:
                    WorkoutHistoryView()
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
                guard seedStatus == .loading else { return }

                try resetUITestFixtureStore()
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

    #if DEBUG
    @MainActor
    private func resetUITestFixtureStore() throws {
        try deleteAll(WorkoutSet.self)
        try deleteAll(WorkoutSessionExerciseSnapshot.self)
        try deleteAll(WorkoutSession.self)
        try deleteAll(TrainingDayOverride.self)
        try deleteAll(TrainingCycleSlot.self)
        try deleteAll(TrainingCycle.self)
        try deleteAll(TemplateExercise.self)
        try deleteAll(Template.self)
        try deleteAll(Exercise.self)
        try modelContext.save()
    }

    private func deleteAll<T: PersistentModel>(_ modelType: T.Type) throws {
        for model in try modelContext.fetch(FetchDescriptor<T>()) {
            modelContext.delete(model)
        }
    }
    #endif
}

private enum SeedStatus: Equatable {
    case loading
    case ready
    case failed(String)
}

#Preview {
    ContentView(notificationRouter: NotificationNavigationRouter())
        .modelContainer(
            for: DaaiZekBroSchema.modelTypes,
            inMemory: true
        )
}
