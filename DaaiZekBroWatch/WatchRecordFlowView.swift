import Combine
import Foundation
import SwiftUI
import UserNotifications
import WatchKit

struct WatchRecordFlowView: View {
    @Environment(\.scenePhase) private var scenePhase

    let snapshot: WatchWorkoutSnapshot
    let exercise: WatchWorkoutSnapshot.Exercise
    @ObservedObject var sessionManager: WatchSessionManager

    @State private var weight = 0.0
    @State private var reps = 10
    @State private var hasTouchedWeight = false
    @State private var hasTouchedReps = false
    @State private var selectedRPE: Int?
    @State private var selectedSide = "left"
    @State private var isSubmitting = false
    @State private var feedback: SubmissionFeedback?
    @State private var submitTask: Task<Void, Never>?
    @State private var restTimerCore = WatchRestTimerCore()
    @State private var restTimerState: WatchRestTimerState?
    @State private var restTimerPermissionTask: Task<Void, Never>?
    @State private var restTimerHapticStatus = WatchRestTimerHapticStatus.pending
    @State private var deferredHapticAuthorization = DeferredHapticAuthorization.unknown
    @State private var lastScenePhase: ScenePhase = .active
    @State private var isResolvingRestTimerActivation = false

    private let rpeValues = [6, 7, 8, 9, 10]
    private let restTimerTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let restTimerState {
                WatchRestTimerView(
                    state: restTimerState,
                    hapticStatusText: restTimerHapticStatusText,
                    addThirtySeconds: addThirtySecondsToRestTimer,
                    skip: clearRestTimer,
                    next: clearRestTimer
                )
            } else {
                recordForm
            }
        }
        .background(WatchPalette.oledBlack.ignoresSafeArea())
        .navigationTitle(exercise.name)
        .tint(WatchPalette.pump)
        .onAppear {
            selectedSide = sessionManager.inferredNextSide(for: currentExercise)
            lastScenePhase = scenePhase
            refreshRestTimer(at: Date(), isActive: scenePhase == .active)
        }
        .onChange(of: currentExercise.completedSetCount) { _, _ in
            guard exercise.isUnilateral, isSubmitting == false else {
                return
            }

            selectedSide = sessionManager.inferredNextSide(for: currentExercise)
        }
        .onChange(of: scenePhase) { _, nextPhase in
            let previousPhase = lastScenePhase
            lastScenePhase = nextPhase

            if nextPhase == .active {
                refreshRestTimerAfterActivation(wasInactive: previousPhase != .active)
            } else {
                refreshRestTimer(at: Date(), isActive: false)
            }
        }
        .onReceive(restTimerTicker) { date in
            guard scenePhase == .active else {
                return
            }

            if isResolvingRestTimerActivation {
                refreshRestTimerDisplay(at: date)
            } else {
                refreshRestTimer(at: date, isActive: true)
            }
        }
        .onDisappear {
            submitTask?.cancel()
            restTimerPermissionTask?.cancel()
            isResolvingRestTimerActivation = false
        }
    }

    private var recordForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                referenceCard

                if sessionManager.canSubmitSet == false {
                    connectionBanner
                }

                if exercise.isUnilateral {
                    sideSection
                }

                inputSection
                rpeSection

                if let feedback {
                    feedbackView(feedback)
                }

                submitButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(WatchPalette.oledBlack.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .disabled(isSubmitting)
    }

    private var currentExercise: WatchWorkoutSnapshot.Exercise {
        guard sessionManager.snapshot?.sessionID == snapshot.sessionID else {
            return exercise
        }

        return sessionManager.snapshot?.exercises.first {
            $0.exerciseOrderIndex == exercise.exerciseOrderIndex
        } ?? exercise
    }

    private var canSubmit: Bool {
        sessionManager.canSubmitSet
            && hasTouchedWeight
            && hasTouchedReps
            && isSubmitting == false
            && currentDraft.canSubmit(isUnilateral: exercise.isUnilateral)
    }

    private var currentDraft: WatchRecordDraft {
        WatchRecordDraft(
            weight: Self.normalizedWeight(weight),
            reps: reps,
            rpe: selectedRPE,
            side: exercise.isUnilateral ? selectedSide : nil,
            reference: currentExercise.lastSetReference
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { weight },
            set: { nextValue in
                weight = Self.normalizedWeight(nextValue)
                hasTouchedWeight = true
                feedback = nil
            }
        )
    }

    private var repsBinding: Binding<Int> {
        Binding(
            get: { reps },
            set: { nextValue in
                reps = min(200, max(1, nextValue))
                hasTouchedReps = true
                feedback = nil
            }
        )
    }

    private var repsCrownBinding: Binding<Double> {
        Binding(
            get: { Double(reps) },
            set: { nextValue in
                reps = min(200, max(1, Int(nextValue.rounded())))
                hasTouchedReps = true
                feedback = nil
            }
        )
    }

    private var referenceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("参考")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.faintText)

            Text(referenceText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 6) {
                referenceMetric(title: "已完成", value: "\(currentExercise.completedSetCount) 组", color: WatchPalette.caramel)
                referenceMetric(title: "休息", value: "\(currentExercise.defaultRestSeconds) 秒", color: WatchPalette.secondaryText)
                referenceMetric(title: "单位", value: currentExercise.weightUnit, color: WatchPalette.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchPalette.row)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WatchPalette.rowStroke, lineWidth: 1)
        }
    }

    private var referenceText: String {
        guard let reference = currentExercise.lastSetReference else {
            return "上组 暂无参考"
        }

        return "上组 \(WatchRecordFormat.weight(reference.weight)) x \(reference.reps) · \(referenceSourceText(reference.source))"
    }

    private func referenceSourceText(_ source: String) -> String {
        source == "currentSession" ? "本场" : "历史"
    }

    private func referenceMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(WatchPalette.faintText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionBanner: some View {
        Text(connectionMessage)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(WatchPalette.offline)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchPalette.offlineBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var connectionMessage: String {
        switch sessionManager.connectionStatus {
        case .reachable:
            "等待实时训练数据"
        case .unreachable, .inactive, .failed, .unsupported:
            "手机暂不可达"
        }
    }

    private var sideSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("侧别")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.faintText)

            HStack(spacing: 6) {
                sideButton("left", title: "左")
                sideButton("right", title: "右")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchPalette.row)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sideButton(_ side: String, title: String) -> some View {
        Button {
            selectedSide = side
            feedback = nil
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(selectedSide == side ? WatchPalette.oledBlack : WatchPalette.primaryText)
                .background(selectedSide == side ? WatchPalette.pump : WatchPalette.banner)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var inputSection: some View {
        VStack(spacing: 4) {
            weightStepper

            Rectangle()
                .fill(WatchPalette.rowStroke)
                .frame(height: 1)

            repsStepper
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(WatchPalette.row)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var weightStepper: some View {
        Stepper(value: weightBinding, in: 0...500, step: 2.5) {
            inputLabel(
                title: "重量",
                value: hasTouchedWeight ? "\(WatchRecordFormat.weight(weight)) \(currentExercise.weightUnit)" : "-- \(currentExercise.weightUnit)"
            )
        }
        .focusable(isSubmitting == false)
        .digitalCrownRotation(
            weightBinding,
            from: 0,
            through: 500,
            by: 2.5,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    private var repsStepper: some View {
        Stepper(value: repsBinding, in: 1...200, step: 1) {
            inputLabel(
                title: "次数",
                value: hasTouchedReps ? "\(reps) 次" : "-- 次"
            )
        }
        .focusable(isSubmitting == false)
        .digitalCrownRotation(
            repsCrownBinding,
            from: 1,
            through: 200,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
    }

    private func inputLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WatchPalette.faintText)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rpeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RPE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(WatchPalette.faintText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                ForEach(rpeValues, id: \.self) { rpe in
                    rpeButton(rpe)
                }
            }
        }
        .padding(10)
        .background(WatchPalette.row)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func rpeButton(_ rpe: Int) -> some View {
        Button {
            selectedRPE = selectedRPE == rpe ? nil : rpe
            feedback = nil
        } label: {
            Text("\(rpe)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(selectedRPE == rpe ? WatchPalette.oledBlack : WatchPalette.primaryText)
                .background(selectedRPE == rpe ? rpeColor(rpe) : WatchPalette.banner)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func rpeColor(_ rpe: Int) -> Color {
        switch rpe {
        case 6:
            WatchPalette.sync
        case 7, 8:
            WatchPalette.caramel
        default:
            WatchPalette.pump
        }
    }

    private func feedbackView(_ feedback: SubmissionFeedback) -> some View {
        Text(feedback.message)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(feedback.isSuccess ? WatchPalette.sync : WatchPalette.offline)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(feedback.isSuccess ? WatchPalette.syncBackground : WatchPalette.offlineBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 6) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }

                Text(isSubmitting ? "同步中" : "记录")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(canSubmit ? WatchPalette.pump : WatchPalette.banner)
        .foregroundStyle(canSubmit ? WatchPalette.oledBlack : WatchPalette.faintText)
        .disabled(canSubmit == false)
    }

    private func submit() {
        guard canSubmit else {
            return
        }

        isSubmitting = true
        feedback = nil

        let draft = currentDraft
        let sessionID = snapshot.sessionID
        let exerciseForSubmission = currentExercise

        submitTask?.cancel()
        submitTask = Task {
            do {
                try await sessionManager.submitSet(
                    draft,
                    sessionID: sessionID,
                    exercise: exerciseForSubmission
                )
                try Task.checkCancellation()
                await MainActor.run {
                    handleSubmissionSuccess(
                        submittedDraft: draft,
                        submittedExercise: exerciseForSubmission
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    handleSubmissionFailure(error)
                }
            }
        }
    }

    private func handleSubmissionSuccess(
        submittedDraft: WatchRecordDraft,
        submittedExercise: WatchWorkoutSnapshot.Exercise
    ) {
        isSubmitting = false
        feedback = SubmissionFeedback(message: "已同步", isSuccess: true)
        WKInterfaceDevice.current().play(.success)
        resetDraft()
        startRestTimerIfNeeded(after: submittedDraft, exercise: submittedExercise)

        if exercise.isUnilateral {
            selectedSide = sessionManager.inferredNextSide(for: currentExercise)
        }
    }

    private func handleSubmissionFailure(_ error: Error) {
        isSubmitting = false
        feedback = SubmissionFeedback(message: error.localizedDescription, isSuccess: false)
        WKInterfaceDevice.current().play(.failure)
    }

    private func resetDraft() {
        weight = 0
        reps = 10
        hasTouchedWeight = false
        hasTouchedReps = false
        selectedRPE = nil
    }

    private static func normalizedWeight(_ value: Double) -> Double {
        min(500, max(0, (value / 2.5).rounded() * 2.5))
    }

    private func startRestTimerIfNeeded(
        after draft: WatchRecordDraft,
        exercise: WatchWorkoutSnapshot.Exercise
    ) {
        guard WatchRestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: exercise.isUnilateral,
            completedSide: Self.completedSide(from: draft.side)
        ) else {
            return
        }

        restTimerHapticStatus = .pending
        deferredHapticAuthorization = .unknown
        isResolvingRestTimerActivation = false
        restTimerPermissionTask?.cancel()

        let startedAt = Date()
        _ = restTimerCore.start(
            sessionID: snapshot.sessionID,
            exerciseOrderIndex: exercise.exerciseOrderIndex,
            exerciseName: exercise.name,
            restSeconds: exercise.defaultRestSeconds,
            startedAt: startedAt,
            now: startedAt
        )
        restTimerState = restTimerCore.state
        updateDeferredHapticAuthorization()
    }

    private func refreshRestTimer(at date: Date, isActive: Bool, crossedInactive: Bool = false) {
        guard restTimerState != nil else {
            return
        }

        if crossedInactive {
            let inactiveEffect = restTimerCore.refresh(
                now: date,
                isActive: false,
                canNotify: deferredHapticAuthorization == .allowed
            )
            restTimerState = restTimerCore.state
            handleRestTimerEffect(inactiveEffect)
        }

        let effect = restTimerCore.refresh(
            now: date,
            isActive: isActive,
            canNotify: deferredHapticAuthorization == .allowed
        )
        restTimerState = restTimerCore.state
        handleRestTimerEffect(effect)
    }

    private func refreshRestTimerDisplay(at date: Date) {
        restTimerState = restTimerCore.displayState(now: date)
    }

    private func addThirtySecondsToRestTimer() {
        _ = restTimerCore.addThirtySeconds(now: Date())
        restTimerState = restTimerCore.state
        restTimerHapticStatus = .pending
    }

    private func clearRestTimer() {
        restTimerCore.skip()
        restTimerState = restTimerCore.state
        restTimerHapticStatus = .pending
        deferredHapticAuthorization = .unknown
        isResolvingRestTimerActivation = false
        restTimerPermissionTask?.cancel()
        restTimerPermissionTask = nil
    }

    private func handleRestTimerEffect(_ effect: WatchRestTimerEffect) {
        switch effect {
        case .none:
            if restTimerState?.isZeroed == true, deferredHapticAuthorization == .denied {
                restTimerHapticStatus = .unauthorized
            }
        case .playCompletionHaptic:
            WKInterfaceDevice.current().play(.notification)
            restTimerHapticStatus = .reminded
        }
    }

    private func updateDeferredHapticAuthorization() {
        guard restTimerState != nil, deferredHapticAuthorization == .unknown else {
            return
        }

        restTimerPermissionTask?.cancel()
        restTimerPermissionTask = Task {
            let isAllowed = await Self.isDeferredHapticAuthorized()

            await MainActor.run {
                deferredHapticAuthorization = isAllowed ? .allowed : .denied
                refreshRestTimer(at: Date(), isActive: lastScenePhase == .active)
            }
        }
    }

    private func refreshRestTimerAfterActivation(wasInactive: Bool) {
        guard restTimerState != nil else {
            isResolvingRestTimerActivation = false
            return
        }

        guard wasInactive else {
            isResolvingRestTimerActivation = false
            refreshRestTimer(at: Date(), isActive: true)
            return
        }

        isResolvingRestTimerActivation = true
        refreshRestTimerDisplay(at: Date())
        restTimerPermissionTask?.cancel()
        restTimerPermissionTask = Task {
            let isAllowed = await Self.isDeferredHapticAuthorized()

            await MainActor.run {
                guard Task.isCancelled == false, restTimerState != nil, lastScenePhase == .active else {
                    isResolvingRestTimerActivation = false
                    return
                }

                deferredHapticAuthorization = isAllowed ? .allowed : .denied
                refreshRestTimer(at: Date(), isActive: true, crossedInactive: wasInactive)
                isResolvingRestTimerActivation = false
            }
        }
    }

    private var restTimerHapticStatusText: String {
        switch restTimerHapticStatus {
        case .pending:
            deferredHapticAuthorization == .denied ? "未授权 · 仅展示归零" : "已归零"
        case .reminded:
            "已震动提醒"
        case .unauthorized:
            "未授权 · 仅展示归零"
        }
    }

    private static func completedSide(from side: String?) -> WatchRestTimerCompletedSide? {
        switch side {
        case "left":
            .left
        case "right":
            .right
        default:
            nil
        }
    }

    private static func isDeferredHapticAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

private struct SubmissionFeedback: Equatable {
    let message: String
    let isSuccess: Bool
}

private enum WatchRestTimerHapticStatus {
    case pending
    case reminded
    case unauthorized
}

private enum DeferredHapticAuthorization {
    case unknown
    case allowed
    case denied
}

private enum WatchRecordFormat {
    static func weight(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 1
        formatter.maximumFractionDigits = 1

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#Preview("记录双侧") {
    NavigationStack {
        WatchRecordFlowView(
            snapshot: .preview,
            exercise: WatchWorkoutSnapshot.preview.exercises[0],
            sessionManager: WatchSessionManager.preview(
                connectionStatus: .reachable,
                isTraining: true,
                snapshot: .preview
            )
        )
    }
}

#Preview("记录单侧") {
    NavigationStack {
        WatchRecordFlowView(
            snapshot: .preview,
            exercise: WatchWorkoutSnapshot.preview.exercises[1],
            sessionManager: WatchSessionManager.preview(
                connectionStatus: .reachable,
                isTraining: true,
                snapshot: .preview
            )
        )
    }
}
