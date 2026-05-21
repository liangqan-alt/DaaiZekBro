//
//  ContentView.swift
//  DaaiZekBro
//
//  Created by liangqan on 2026/5/20.
//

import SwiftUI
import SwiftData

enum AppRoute: Hashable {
    case currentWorkout(sessionID: UUID)
    case exerciseLogging(sessionID: UUID, exerciseName: String)
    case settings
}

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

struct TemplateListView: View {
    @Binding var path: [AppRoute]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Template.name) private var templates: [Template]
    @Query private var sessions: [WorkoutSession]
    @State private var pendingTemplateName: String?
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                if let currentOpenSession {
                    continueButton(for: currentOpenSession)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(orderedTemplates) { template in
                        DZTemplateCard(
                            name: template.name,
                            exerciseCount: template.exercises.count
                        ) {
                            startOrResolveConflict(for: template)
                        }
                        .accessibilityIdentifier("template-\(template.name)")
                    }
                }
            }
            .padding(DZMetric.contentPadding)
        }
        .dzScreenBackground()
        .navigationTitle("训练模板")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("daaizeibro-logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
        .confirmationDialog(
            "已有未结束的训练",
            isPresented: Binding(
                get: { pendingTemplateName != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingTemplateName = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("继续当前训练") {
                continueCurrentWorkout()
            }

            Button("结束当前并新建") {
                resolveConflictByEndingAndCreating()
            }

            Button("丢弃当前并新建", role: .destructive) {
                resolveConflictByDiscardingAndCreating()
            }

            Button("取消", role: .cancel) {
                pendingTemplateName = nil
            }
        } message: {
            Text("请选择如何处理当前训练")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var orderedTemplates: [Template] {
        let templatesByName = Dictionary(uniqueKeysWithValues: templates.map { ($0.name, $0) })

        return SeedData.templateExerciseNames.compactMap { templatesByName[$0.name] }
    }

    private var currentOpenSession: WorkoutSession? {
        sessions
            .filter { $0.endedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private func continueButton(for session: WorkoutSession) -> some View {
        Button {
            path.append(.currentWorkout(sessionID: session.id))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("继续当前训练")
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text(displayName(for: session))

                        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                            Text("已 \(durationText(from: session.startedAt, to: timeline.date))")
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(DZColor.fgOnPump.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(DZColor.fgOnPump.opacity(0.85))
            }
            .foregroundStyle(DZColor.fgOnPump)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DZColor.pump500)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .shadow(color: DZColor.ink900.opacity(0.12), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func startOrResolveConflict(for template: Template) {
        do {
            if try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) == nil {
                let session = try WorkoutSessionLifecycle.createSession(for: template, in: modelContext)
                path.append(.currentWorkout(sessionID: session.id))
            } else {
                pendingTemplateName = template.name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func continueCurrentWorkout() {
        do {
            guard let session = try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) else {
                pendingTemplateName = nil
                return
            }

            pendingTemplateName = nil
            path.append(.currentWorkout(sessionID: session.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveConflictByEndingAndCreating() {
        guard let template = pendingTemplate else {
            pendingTemplateName = nil
            return
        }

        do {
            if let session = try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) {
                try WorkoutSessionLifecycle.end(session, in: modelContext)
                UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
            }

            let newSession = try WorkoutSessionLifecycle.createSession(for: template, in: modelContext)
            pendingTemplateName = nil
            path.append(.currentWorkout(sessionID: newSession.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveConflictByDiscardingAndCreating() {
        guard let template = pendingTemplate else {
            pendingTemplateName = nil
            return
        }

        do {
            if let session = try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) {
                try WorkoutSessionLifecycle.discard(session, in: modelContext)
                UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
            }

            let newSession = try WorkoutSessionLifecycle.createSession(for: template, in: modelContext)
            pendingTemplateName = nil
            path.append(.currentWorkout(sessionID: newSession.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var pendingTemplate: Template? {
        guard let pendingTemplateName else { return nil }

        return templates.first { $0.name == pendingTemplateName }
    }
}

struct CurrentWorkoutView: View {
    let sessionID: UUID
    @Binding var path: [AppRoute]
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]
    @Query private var templates: [Template]
    @Query private var sets: [WorkoutSet]
    @State private var isShowingDiscardConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                        header(for: session)

                        DZSection("动作") {
                            if exercises.isEmpty {
                                Text("未找到模板动作")
                                    .foregroundStyle(DZColor.ink700)
                                    .padding(14)
                            } else {
                                ForEach(Array(exercises.enumerated()), id: \.element.name) { index, exercise in
                                    if index > 0 {
                                        DZDivider()
                                    }

                                    NavigationLink(
                                        value: AppRoute.exerciseLogging(
                                            sessionID: sessionID,
                                            exerciseName: exercise.name
                                        )
                                    ) {
                                        ExerciseRow(
                                            exercise: exercise,
                                            recordedSetCount: setCounts[exercise.name, default: 0]
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(DZMetric.contentPadding)
                }
                .dzScreenBackground()
                .navigationTitle(displayName(for: session))
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("结束训练") {
                            endWorkout(session)
                        }

                        Menu {
                            Button("丢弃训练", role: .destructive) {
                                isShowingDiscardConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .confirmationDialog(
                    "丢弃训练？",
                    isPresented: $isShowingDiscardConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("丢弃训练", role: .destructive) {
                        discardWorkout(session)
                    }

                    Button("取消", role: .cancel) {}
                } message: {
                    Text("这会删除当前训练和已记录组数。")
                }
            } else {
                ContentUnavailableView(
                    "训练不存在",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("请返回模板列表重新选择训练。")
                )
            }
        }
        .background(DZColor.cream50.ignoresSafeArea())
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var session: WorkoutSession? {
        sessions.first { $0.id == sessionID }
    }

    private var resolvedTemplate: Template? {
        guard let session else { return nil }

        return session.template ?? templates.first { $0.name == session.templateNameSnapshot }
    }

    private var exercises: [Exercise] {
        guard let resolvedTemplate else {
            return []
        }

        return WorkoutSessionLifecycle.orderedExercises(for: resolvedTemplate)
    }

    private var setCounts: [String: Int] {
        var counts: [String: Int] = [:]

        for set in sets where set.session?.id == sessionID {
            let exerciseName = set.exerciseNameSnapshot.isEmpty ? set.exercise?.name : set.exerciseNameSnapshot

            guard let exerciseName, exerciseName.isEmpty == false else {
                continue
            }

            counts[exerciseName, default: 0] += 1
        }

        return counts
    }

    private func header(for session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次训练 · Session")
                .font(.caption.weight(.bold))
                .foregroundStyle(DZColor.ink700)
                .textCase(.uppercase)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    Text(durationText(from: session.startedAt, to: session.endedAt ?? timeline.date))
                        .dzNumeric(size: 32, weight: .bold)
                }

                Text("已持续")
                    .font(.subheadline)
                    .foregroundStyle(DZColor.ink700)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dzCardStyle()
    }

    private func endWorkout(_ session: WorkoutSession) {
        do {
            try WorkoutSessionLifecycle.end(session, in: modelContext)
            UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
            path.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout(_ session: WorkoutSession) {
        do {
            try WorkoutSessionLifecycle.discard(session, in: modelContext)
            UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
            path.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise
    let recordedSetCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(DZColor.ink900)

                Text("休息 \(exercise.defaultRestSeconds) 秒\(exercise.isUnilateral ? " · 单侧" : "")")
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
            }

            Spacer()

            Text("\(recordedSetCount) 组")
                .dzNumeric(size: 15)
                .foregroundStyle(recordedSetCount > 0 ? DZColor.pump500 : DZColor.ink700)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DZColor.fgFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private enum SeedStatus: Equatable {
    case loading
    case ready
    case failed(String)
}

private func displayName(for session: WorkoutSession) -> String {
    if let templateName = session.template?.name, templateName.isEmpty == false {
        return templateName
    }

    return session.templateNameSnapshot.isEmpty ? "未命名训练" : session.templateNameSnapshot
}

private func durationText(from startDate: Date, to endDate: Date) -> String {
    let elapsedSeconds = max(0, Int(endDate.timeIntervalSince(startDate)))
    let minutes = elapsedSeconds / 60
    let seconds = elapsedSeconds % 60

    return String(format: "%02d:%02d", minutes, seconds)
}

#Preview {
    ContentView(notificationRouter: NotificationNavigationRouter())
        .modelContainer(
            for: [Exercise.self, Template.self, WorkoutSession.self, WorkoutSet.self],
            inMemory: true
        )
}
