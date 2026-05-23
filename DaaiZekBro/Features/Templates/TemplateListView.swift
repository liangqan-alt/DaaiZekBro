import SwiftData
import SwiftUI

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

    private var pendingTemplate: Template? {
        guard let pendingTemplateName else { return nil }

        return templates.first { $0.name == pendingTemplateName }
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
            .dzShadowSM()
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
}
