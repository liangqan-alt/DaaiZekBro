import Combine
import Foundation
import SwiftUI
import SwiftData
import UIKit

struct ExerciseLoggingView: View {
    let sessionID: UUID
    let exerciseName: String

    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]
    @Query private var sets: [WorkoutSet]
    @State private var selectedSide: Side = .left
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var selectedRPE: Int?
    @State private var isRPEExpanded = false
    @State private var pendingDeleteSet: WorkoutSet?
    @State private var errorMessage: String?
    @State private var didLoadInitialDraft = false
    @StateObject private var restTimer = RestTimerModel()
    @State private var timerMutationTask: Task<Void, Never>?
    private let restTimerTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let session, let exercise {
                List {
                    Section {
                        LabeledContent("模板", value: displayName(for: session))
                        LabeledContent("默认休息", value: "\(exercise.defaultRestSeconds) 秒")
                    }

                    if let restTimerState = restTimer.state {
                        restTimerSection(restTimerState)
                    } else {
                        if exercise.isUnilateral {
                            sideSection
                        }

                        referenceSection
                        inputSection
                        rpeSection
                        completionSection(for: exercise)
                    }

                    recordedSetsSection(for: exercise)
                }
            } else {
                ContentUnavailableView(
                    "记录页不可用",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("请返回当前训练页重新选择动作。")
                )
            }
        }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadInitialDraft)
        .onChange(of: selectedSide) { _, _ in
            prefillFromLastSet()
        }
        .onChange(of: sideBalanceKey) { _, _ in
            syncSideWithRecordedSets()
        }
        .onReceive(restTimerTicker) { date in
            guard restTimer.tick(now: date) else { return }

            finishRestTimer()
        }
        .onDisappear {
            restTimer.stopForegroundTimerKeepingNotification()
        }
        .confirmationDialog(
            "删除这组记录？",
            isPresented: Binding(
                get: { pendingDeleteSet != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeleteSet = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive, action: deletePendingSet)
            Button("取消", role: .cancel) {
                pendingDeleteSet = nil
            }
        } message: {
            Text("删除后剩余组会按完成时间重新编号。")
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

    private var session: WorkoutSession? {
        sessions.first { $0.id == sessionID }
    }

    private var exercise: Exercise? {
        exercises.first { $0.name == exerciseName }
    }

    private var currentSide: Side? {
        exercise?.isUnilateral == true ? selectedSide : nil
    }

    private var parsedWeight: Double? {
        let normalizedText = weightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard normalizedText.isEmpty == false, let value = Double(normalizedText), value >= 0 else {
            return nil
        }

        return value
    }

    private var parsedReps: Int? {
        let trimmedText = repsText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedText.isEmpty == false, let reps = Int(trimmedText), reps >= 1 else {
            return nil
        }

        return reps
    }

    private var canCompleteSet: Bool {
        session?.endedAt == nil && parsedWeight != nil && parsedReps != nil
    }

    private var loggedSets: [WorkoutSet] {
        WorkoutSetLogging.sortedByCompletedAt(
            sets.filter { set in
                set.session?.id == sessionID && WorkoutSetLogging.exerciseName(for: set) == exerciseName
            }
        )
    }

    private var leftSets: [WorkoutSet] {
        loggedSets.filter { $0.side == .left }
    }

    private var rightSets: [WorkoutSet] {
        loggedSets.filter { $0.side == .right }
    }

    private var bilateralSets: [WorkoutSet] {
        loggedSets.filter { $0.side == nil }
    }

    private var sideBalanceKey: String {
        "\(leftSets.count)-\(rightSets.count)"
    }

    private var sidePrompt: String? {
        guard exercise?.isUnilateral == true else { return nil }

        if leftSets.count > rightSets.count {
            return "上一组左侧已完成，请完成右侧"
        }

        if leftSets.count < rightSets.count {
            return "上一组右侧已完成，请完成左侧"
        }

        return nil
    }

    private var lastReferenceSet: WorkoutSet? {
        sets
            .filter { set in
                set.exerciseNameSnapshot == exerciseName && set.side == currentSide
            }
            .sorted { lhs, rhs in
                lhs.completedAt > rhs.completedAt
            }
            .first
    }

    private var sideSection: some View {
        Section {
            Picker("侧别", selection: $selectedSide) {
                Text("左").tag(Side.left)
                Text("右").tag(Side.right)
            }
            .pickerStyle(.segmented)
            .disabled(sidePrompt != nil)
            .accessibilityIdentifier("side-picker")

            if let sidePrompt {
                Text(sidePrompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var referenceSection: some View {
        Section {
            if let lastReferenceSet {
                let sidePrefix = currentSide.map { "（\(displayName(for: $0))）" } ?? ""

                LabeledContent(
                    "上次\(sidePrefix)",
                    value: "\(displayWeight(lastReferenceSet.weight)) kg × \(lastReferenceSet.reps)"
                )
            } else {
                Text("暂无上次记录")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inputSection: some View {
        Section("本组") {
            NumericEntryRow(
                title: "重量",
                unit: "kg",
                text: $weightText,
                keyboardType: .decimalPad,
                decrement: { adjustWeight(by: -2.5) },
                increment: { adjustWeight(by: 2.5) }
            )

            HStack {
                Button("-2.5") {
                    adjustWeight(by: -2.5)
                }

                Button("+2.5") {
                    adjustWeight(by: 2.5)
                }

                Button("+5") {
                    adjustWeight(by: 5)
                }
            }
            .buttonStyle(.bordered)

            NumericEntryRow(
                title: "次数",
                unit: "次",
                text: $repsText,
                keyboardType: .numberPad,
                decrement: { adjustReps(by: -1) },
                increment: { adjustReps(by: 1) }
            )
        }
    }

    private var rpeSection: some View {
        Section {
            DisclosureGroup("RPE（可选）", isExpanded: $isRPEExpanded) {
                HStack {
                    ForEach(WorkoutSetLogging.allowedRPEValues, id: \.self) { rpe in
                        Button {
                            selectedRPE = selectedRPE == rpe ? nil : rpe
                        } label: {
                            Text("\(rpe)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedRPE == rpe ? .accentColor : nil)
                        .accessibilityIdentifier("rpe-\(rpe)")
                    }
                }

                if selectedRPE != nil {
                    Button("清除 RPE", role: .destructive) {
                        selectedRPE = nil
                    }
                }
            }

            if let selectedRPE {
                LabeledContent("当前 RPE", value: "\(selectedRPE)")
            }
        }
    }

    private func completionSection(for exercise: Exercise) -> some View {
        Section {
            Button(action: completeSet) {
                Text(completionButtonTitle(for: exercise))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(canCompleteSet == false)
            .accessibilityIdentifier("complete-set-button")
        }
    }

    private func restTimerSection(_ state: RestTimerState) -> some View {
        Section {
            RestTimerView(
                state: state,
                addThirtySeconds: extendRestTimer,
                skip: skipRestTimer
            )
        }
    }

    private func recordedSetsSection(for exercise: Exercise) -> some View {
        Section("已记录组") {
            if loggedSets.isEmpty {
                Text("暂无记录")
                    .foregroundStyle(.secondary)
            } else if exercise.isUnilateral {
                HStack(alignment: .top, spacing: 16) {
                    RecordedSetColumn(title: "左", sets: leftSets, onDelete: confirmDelete)
                    RecordedSetColumn(title: "右", sets: rightSets, onDelete: confirmDelete)
                }
            } else {
                ForEach(bilateralSets) { set in
                    LoggedSetButton(set: set, showsSide: false) {
                        confirmDelete(set)
                    }
                }
            }
        }
    }

    private func loadInitialDraft() {
        guard didLoadInitialDraft == false else { return }

        syncSideWithRecordedSets()
        prefillFromLastSet()
        didLoadInitialDraft = true
    }

    private func syncSideWithRecordedSets() {
        guard exercise?.isUnilateral == true else {
            return
        }

        do {
            selectedSide = try WorkoutSetLogging.inferredNextSide(
                sessionID: sessionID,
                exerciseName: exerciseName,
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prefillFromLastSet() {
        do {
            guard let values = try WorkoutSetLogging.lastValues(
                exerciseName: exerciseName,
                side: currentSide,
                in: modelContext
            ) else {
                weightText = ""
                repsText = ""
                selectedRPE = nil
                return
            }

            weightText = displayWeight(values.weight)
            repsText = "\(values.reps)"
            selectedRPE = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func adjustWeight(by delta: Double) {
        let currentWeight = parsedWeight ?? 0
        weightText = displayWeight(max(0, currentWeight + delta))
    }

    private func adjustReps(by delta: Int) {
        let currentReps = parsedReps ?? 0
        repsText = "\(max(1, currentReps + delta))"
    }

    private func completeSet() {
        guard let weight = parsedWeight, let reps = parsedReps, let exercise else {
            return
        }

        do {
            let savedSet = try WorkoutSetLogging.recordSet(
                sessionID: sessionID,
                exerciseName: exerciseName,
                weight: weight,
                reps: reps,
                rpe: selectedRPE,
                side: exercise.isUnilateral ? selectedSide : nil,
                in: modelContext
            )

            let completedSide = exercise.isUnilateral ? selectedSide : nil

            if RestTimerStartPolicy.shouldStartAfterCompletedSet(
                isUnilateral: exercise.isUnilateral,
                completedSide: completedSide
            ) {
                startRestTimer(restSeconds: exercise.defaultRestSeconds, startedAt: savedSet.completedAt)

                if exercise.isUnilateral {
                    selectedSide = .left
                }
            } else if exercise.isUnilateral {
                restTimer.stopForegroundTimerKeepingNotification()
                selectedSide = .right
            }

            prefillFromLastSet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRestTimer(restSeconds: Int, startedAt: Date) {
        performTimerMutation {
            await restTimer.start(
                restSeconds: restSeconds,
                sessionID: sessionID,
                exerciseName: exerciseName,
                startedAt: startedAt
            )
        }
    }

    private func extendRestTimer() {
        performTimerMutation {
            await restTimer.addThirtySeconds()
        }
    }

    private func skipRestTimer() {
        restTimer.stopForegroundTimerKeepingNotification()
        performTimerMutation {
            await restTimer.skip()
        }
        finishRestTimer()
    }

    private func performTimerMutation(_ operation: @escaping @MainActor () async -> Void) {
        timerMutationTask?.cancel()
        timerMutationTask = Task { @MainActor in
            await operation()
        }
    }

    private func finishRestTimer() {
        if exercise?.isUnilateral == true {
            selectedSide = .left
        }

        prefillFromLastSet()
    }

    private func completionButtonTitle(for exercise: Exercise) -> String {
        guard exercise.isUnilateral else {
            return "完成本组 · 开始计时"
        }

        switch selectedSide {
        case .left:
            return "完成左侧"
        case .right:
            return "完成右侧 · 开始计时"
        }
    }

    private func confirmDelete(_ set: WorkoutSet) {
        pendingDeleteSet = set
    }

    private func deletePendingSet() {
        guard let pendingDeleteSet else {
            return
        }

        do {
            try WorkoutSetLogging.deleteAndRenumber(pendingDeleteSet, in: modelContext)
            self.pendingDeleteSet = nil
            syncSideWithRecordedSets()
            prefillFromLastSet()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NumericEntryRow: View {
    let title: String
    let unit: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack {
            Text(title)

            Spacer()

            Button(action: decrement) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)

            TextField("必填", text: $text)
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityIdentifier("\(title)-field")

            Text(unit)
                .foregroundStyle(.secondary)

            Button(action: increment) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecordedSetColumn: View {
    let title: String
    let sets: [WorkoutSet]
    let onDelete: (WorkoutSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if sets.isEmpty {
                Text("暂无")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sets) { set in
                    LoggedSetButton(set: set, showsSide: false) {
                        onDelete(set)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LoggedSetButton: View {
    let set: WorkoutSet
    let showsSide: Bool
    let onDelete: () -> Void

    var body: some View {
        Button(action: onDelete) {
            HStack {
                Text(rowTitle)

                Spacer()

                if let rpe = set.rpe {
                    Text("RPE \(rpe)")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowTitle: String {
        let sideText = showsSide ? set.side.map { "\(displayName(for: $0)) " } ?? "" : ""

        return "\(sideText)组\(set.setIndex) \(displayWeight(set.weight)) kg × \(set.reps)"
    }
}

private func displayName(for session: WorkoutSession) -> String {
    if let templateName = session.template?.name, templateName.isEmpty == false {
        return templateName
    }

    return session.templateNameSnapshot.isEmpty ? "未命名训练" : session.templateNameSnapshot
}

private func displayName(for side: Side) -> String {
    switch side {
    case .left:
        "左"
    case .right:
        "右"
    }
}

private func displayWeight(_ weight: Double) -> String {
    if weight.rounded() == weight {
        return "\(Int(weight))"
    }

    return String(format: "%.1f", weight)
}
