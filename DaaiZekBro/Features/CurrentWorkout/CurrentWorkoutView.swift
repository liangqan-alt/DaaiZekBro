import SwiftData
import SwiftUI

struct CurrentWorkoutView: View {
    let sessionID: UUID
    @Binding var path: [AppRoute]
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]
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
                                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                                    if index > 0 {
                                        DZDivider()
                                    }

                                    NavigationLink(
                                        value: AppRoute.exerciseLogging(
                                            sessionID: sessionID,
                                            exerciseOrderIndex: exercise.orderIndex,
                                            exerciseName: exercise.name
                                        )
                                    ) {
                                        ExerciseRow(
                                            exercise: exercise,
                                            recordedSetCount: setCounts[exercise.orderIndex, default: 0]
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

    private var exercises: [WorkoutSessionExerciseDescriptor] {
        guard let session else {
            return []
        }

        return (try? WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: modelContext)) ?? []
    }

    private var setCounts: [Int: Int] {
        var counts: [Int: Int] = [:]

        for set in sets where set.session?.id == sessionID {
            counts[set.exerciseOrderIndex, default: 0] += 1
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
            PhoneWatchTrainingStateSync.shared.refresh(in: modelContext)
            path.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardWorkout(_ session: WorkoutSession) {
        do {
            try WorkoutSessionLifecycle.discard(session, in: modelContext)
            UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
            PhoneWatchTrainingStateSync.shared.refresh(in: modelContext)
            path.removeAll()
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

private struct ExerciseRow: View {
    let exercise: WorkoutSessionExerciseDescriptor
    let recordedSetCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(DZColor.ink900)

                Text(metadataText)
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

    private var metadataText: String {
        var parts = [
            "休息 \(exercise.defaultRestSeconds) 秒",
            "单位 \(exercise.weightUnit.label)",
        ]

        if exercise.isUnilateral {
            parts.append("单侧")
        }

        return parts.joined(separator: " · ")
    }
}
