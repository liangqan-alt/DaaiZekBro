import Combine
import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, ObservableObject {
    enum ConnectionStatus: String {
        case reachable
        case unreachable
        case inactive
        case unsupported
        case failed
    }

    enum DisplayState: Equatable {
        case waitingToStart
        case waitingForTrainingData
        case unreachableNoSnapshot
        case training(snapshot: WatchWorkoutSnapshot, isOffline: Bool)
    }

    enum SetSubmissionResult: Equatable {
        case synced
        case pending
        case needsUserAction
        case discarded
    }

    private enum SnapshotSource {
        case live
        case cached
    }

    enum SetSubmissionError: Error, LocalizedError, Equatable {
        case unavailable
        case notReachable
        case missingLiveSnapshot
        case invalidDraft
        case invalidReply
        case rejected(String)
        case transportFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "手表同步不可用"
            case .notReachable:
                "手机暂不可达"
            case .missingLiveSnapshot:
                "等待实时训练数据"
            case .invalidDraft:
                "记录内容无效"
            case .invalidReply:
                "同步回应异常"
            case .rejected(let message):
                message
            case .transportFailed:
                "同步失败"
            }
        }
    }

    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var isTraining: Bool?
    @Published private(set) var snapshot: WatchWorkoutSnapshot?
    @Published private(set) var pendingSubmissionCount: Int
    @Published private(set) var needsUserActionSubmissionCount: Int

    private let session: WCSession?
    private let userDefaults: UserDefaults
    private let pendingStore: WatchPendingSetSubmissionStore
    private var snapshotSource: SnapshotSource?
    private var isAppActive = true
    private var isRetryingPendingSubmissions = false
    private var pendingRetryTask: Task<Void, Never>?
    private static let cachedSnapshotKey = "WatchSessionManager.cachedSnapshot"

    override init() {
        let userDefaults = UserDefaults.standard
        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
            connectionStatus = session.activationState == .activated
                ? (session.isReachable ? .reachable : .unreachable)
                : .inactive
        } else {
            session = nil
            connectionStatus = .unsupported
        }

        self.userDefaults = userDefaults
        pendingStore = WatchPendingSetSubmissionStore(userDefaults: userDefaults)
        pendingSubmissionCount = pendingStore.activeSubmissionCount
        needsUserActionSubmissionCount = pendingStore.needsUserActionCount
        let cachedSnapshot = Self.cachedSnapshot(in: userDefaults)
        snapshot = cachedSnapshot
        snapshotSource = cachedSnapshot == nil ? nil : .cached
        isTraining = cachedSnapshot == nil ? nil : true
        super.init()
    }

    init(
        session: WCSession?,
        connectionStatus: ConnectionStatus,
        isTraining: Bool?,
        snapshot: WatchWorkoutSnapshot? = nil,
        isCachedSnapshot: Bool = false,
        userDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.connectionStatus = connectionStatus
        self.isTraining = isTraining
        self.snapshot = snapshot
        self.userDefaults = userDefaults
        pendingStore = WatchPendingSetSubmissionStore(userDefaults: userDefaults)
        pendingSubmissionCount = pendingStore.activeSubmissionCount
        needsUserActionSubmissionCount = pendingStore.needsUserActionCount
        snapshotSource = snapshot == nil ? nil : (isCachedSnapshot ? .cached : .live)
        super.init()
    }

    var trainingStatusText: String {
        guard let isTraining else {
            return "等待 iPhone 状态"
        }

        return isTraining ? "训练中" : "空闲"
    }

    var canSubmitSet: Bool {
        snapshot != nil && isTraining != false
    }

    var projectedSnapshot: WatchWorkoutSnapshot? {
        snapshot?.applyingPendingSetSubmissions(pendingStore.submissions)
    }

    var displayState: DisplayState {
        if let projectedSnapshot, snapshotSource == .live {
            return .training(snapshot: projectedSnapshot, isOffline: connectionStatus != .reachable)
        }

        switch connectionStatus {
        case .reachable:
            return isTraining == true ? .waitingForTrainingData : .waitingToStart
        case .inactive:
            return isTraining == true ? .waitingForTrainingData : .waitingToStart
        case .unreachable, .failed, .unsupported:
            if let projectedSnapshot, snapshotSource == .cached {
                return .training(snapshot: projectedSnapshot, isOffline: true)
            }

            return .unreachableNoSnapshot
        }
    }

    func activate() {
        guard let session else {
            updateConnectionStatus(.unsupported)
            return
        }

        session.delegate = self
        session.activate()
        updateReachability(for: session)
        retryPendingSubmissionsIfPossible()
    }

    func refreshFromApplicationContext() {
        guard let session else {
            updateConnectionStatus(.unsupported)
            return
        }

        applyMessage(session.receivedApplicationContext)
        updateReachability(for: session)
        retryPendingSubmissionsIfPossible()
    }

    @MainActor
    func updateAppActive(_ isActive: Bool) {
        isAppActive = isActive
        handlePendingReachabilitySideEffects(for: connectionStatus)
    }

    func requestTrainingState() {
        guard let session else {
            updateConnectionStatus(.unsupported)
            return
        }

        updateReachability(for: session)

        guard session.activationState == .activated, session.isReachable else {
            return
        }

        let request = WatchTrainingStateMessage.request(
            requestID: UUID().uuidString,
            sentAt: Date().timeIntervalSince1970
        )

        session.sendMessage(
            request.propertyList,
            replyHandler: { [weak self] reply in
                self?.applyMessage(reply)
            },
            errorHandler: { [weak self] _ in
                self?.updateConnectionStatus(.failed)
            }
        )
    }

    func inferredNextSide(for exercise: WatchWorkoutSnapshot.Exercise) -> String {
        let currentExercise = projectedSnapshot?.exercises.first {
            $0.exerciseOrderIndex == exercise.exerciseOrderIndex
        } ?? exercise

        return WatchRecordDraft.inferredNextSide(
            leftCompletedSetCount: currentExercise.leftCompletedSetCount,
            rightCompletedSetCount: currentExercise.rightCompletedSetCount
        )
    }

    @MainActor
    func submitSet(
        _ draft: WatchRecordDraft,
        sessionID: String,
        exercise: WatchWorkoutSnapshot.Exercise
    ) async throws -> SetSubmissionResult {
        guard let session else {
            updateConnectionStatus(.unsupported)
            throw SetSubmissionError.unavailable
        }

        let nextStatus = connectionStatus(for: session)
        connectionStatus = nextStatus
        restoreCachedSnapshotIfNeeded(for: nextStatus)
        handlePendingReachabilitySideEffects(for: nextStatus)

        guard draft.canSubmit(isUnilateral: exercise.isUnilateral) else {
            throw SetSubmissionError.invalidDraft
        }

        guard let previousSnapshot = snapshot,
              previousSnapshot.sessionID == sessionID,
              let baseExercise = previousSnapshot.exercises.first(where: { $0.exerciseOrderIndex == exercise.exerciseOrderIndex }) else {
            throw SetSubmissionError.missingLiveSnapshot
        }

        let pendingSubmission = try pendingStore.enqueue(
            draft: draft,
            snapshot: previousSnapshot,
            exercise: baseExercise,
            now: Date()
        )
        refreshPendingState()

        guard session.activationState == .activated, session.isReachable else {
            return .pending
        }

        do {
            return try await sendPendingSubmission(pendingSubmission, using: session)
        } catch let error as SetSubmissionError {
            switch error {
            case .rejected:
                throw error
            default:
                pendingStore.markPending(
                    clientSubmissionID: pendingSubmission.clientSubmissionID,
                    now: Date().timeIntervalSince1970
                )
                refreshPendingState()
                return .pending
            }
        } catch {
            pendingStore.markPending(
                clientSubmissionID: pendingSubmission.clientSubmissionID,
                now: Date().timeIntervalSince1970
            )
            refreshPendingState()
            return .pending
        }
    }

    private func applyMessage(_ message: [String: Any]) {
        guard let trainingState = try? WatchTrainingStateMessage(propertyList: message),
              trainingState.kind == .response || trainingState.kind == .update,
              let isTraining = trainingState.isTraining else {
            return
        }

        Task { @MainActor [weak self] in
            self?.apply(trainingState: trainingState, isTraining: isTraining)
        }
    }

    @MainActor
    private func apply(trainingState: WatchTrainingStateMessage, isTraining: Bool) {
        self.isTraining = isTraining

        if let snapshot = trainingState.snapshot {
            pendingStore.removeSyncedSubmissions(includedIn: snapshot)
            snapshotSource = .live
            self.snapshot = snapshot
            cache(snapshot)
            refreshPendingState()
        } else if isTraining == false {
            snapshotSource = nil
            self.snapshot = nil
            clearCachedSnapshot()
        } else {
            snapshotSource = nil
            self.snapshot = nil
        }
    }

    private func updateReachability(
        for session: WCSession,
        didUpdate: ((ConnectionStatus, ConnectionStatus) -> Void)? = nil
    ) {
        let nextStatus = connectionStatus(for: session)
        updateConnectionStatus(nextStatus, didUpdate: didUpdate)
    }

    private func connectionStatus(for session: WCSession) -> ConnectionStatus {
        switch session.activationState {
        case .activated:
            return session.isReachable ? .reachable : .unreachable
        case .inactive, .notActivated:
            return .inactive
        @unknown default:
            return .failed
        }
    }

    private func updateConnectionStatus(
        _ status: ConnectionStatus,
        didUpdate: ((ConnectionStatus, ConnectionStatus) -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let previousStatus = self.connectionStatus
            self.connectionStatus = status
            self.restoreCachedSnapshotIfNeeded(for: status)
            self.handlePendingReachabilitySideEffects(for: status)
            didUpdate?(previousStatus, status)
        }
    }

    @MainActor
    private func restoreCachedSnapshotIfNeeded(for status: ConnectionStatus) {
        guard snapshot == nil, isTraining != false else {
            return
        }

        switch status {
        case .unreachable, .failed, .unsupported:
            guard let cachedSnapshot = Self.cachedSnapshot(in: userDefaults) else {
                return
            }

            snapshot = cachedSnapshot
            snapshotSource = .cached
            isTraining = isTraining ?? true
        case .reachable, .inactive:
            break
        }
    }

    private func sendSubmissionMessage(
        _ propertyList: [String: Any],
        using session: WCSession
    ) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                propertyList,
                replyHandler: { reply in
                    continuation.resume(returning: reply)
                },
                errorHandler: { error in
                    continuation.resume(throwing: error)
                }
            )
        }
    }

    @MainActor
    private func sendPendingSubmission(
        _ pendingSubmission: WatchPendingSetSubmission,
        using session: WCSession,
        manualReviewReason: WatchSetSubmissionManualReviewReason? = nil,
        marksSyncing: Bool = true
    ) async throws -> SetSubmissionResult {
        let now = Date().timeIntervalSince1970
        let wasNeedsUserAction = pendingSubmission.status == .needsUserAction
        if marksSyncing && wasNeedsUserAction == false {
            pendingStore.markSyncing(
                clientSubmissionID: pendingSubmission.clientSubmissionID,
                now: now
            )
            refreshPendingState()
        }

        var propertyList = pendingSubmission.submission.propertyList
        let effectiveManualReviewReason = manualReviewReason ?? pendingSubmission.manualReviewReason
        if let effectiveManualReviewReason {
            propertyList["manualReviewReason"] = effectiveManualReviewReason.rawValue
        }

        do {
            let reply = try await sendSubmissionMessage(propertyList, using: session)
            let ack = try WatchSetSubmissionAck(propertyList: reply)

            guard ack.clientSubmissionID == pendingSubmission.clientSubmissionID else {
                throw SetSubmissionError.invalidReply
            }

            switch ack.status {
            case .saved:
                guard let savedSetIndex = ack.savedSetIndex,
                      let completedSetCount = ack.completedSetCount else {
                    throw SetSubmissionError.invalidReply
                }

                if wasNeedsUserAction {
                    pendingStore.remove(clientSubmissionID: pendingSubmission.clientSubmissionID)
                } else {
                    pendingStore.markSynced(
                        clientSubmissionID: pendingSubmission.clientSubmissionID,
                        now: Date().timeIntervalSince1970,
                        savedSetIndex: savedSetIndex,
                        completedSetCount: completedSetCount
                    )
                }
                refreshPendingState()
                requestTrainingState()
                return .synced
            case .needsUserAction:
                pendingStore.markNeedsUserAction(
                    clientSubmissionID: pendingSubmission.clientSubmissionID,
                    now: Date().timeIntervalSince1970,
                    reason: ack.manualReviewReason ?? effectiveManualReviewReason
                )
                refreshPendingState()
                return .needsUserAction
            case .discarded:
                pendingStore.remove(clientSubmissionID: pendingSubmission.clientSubmissionID)
                refreshPendingState()
                return .discarded
            case .rejected:
                if wasNeedsUserAction {
                    pendingStore.markNeedsUserAction(
                        clientSubmissionID: pendingSubmission.clientSubmissionID,
                        now: Date().timeIntervalSince1970,
                        reason: effectiveManualReviewReason
                    )
                } else {
                    pendingStore.discard(
                        clientSubmissionID: pendingSubmission.clientSubmissionID,
                        now: Date().timeIntervalSince1970
                    )
                }
                refreshPendingState()
                throw SetSubmissionError.rejected(ack.message ?? "同步失败")
            }
        } catch let error as SetSubmissionError {
            throw error
        } catch is WatchSetSubmissionAck.ParseError {
            throw SetSubmissionError.invalidReply
        } catch {
            throw SetSubmissionError.transportFailed(error.localizedDescription)
        }
    }

    @MainActor
    private func handlePendingReachabilitySideEffects(for status: ConnectionStatus) {
        guard status == .reachable, isAppActive else {
            pendingStore.clearReachableForegroundTimers()
            refreshPendingState()
            return
        }

        let now = Date().timeIntervalSince1970
        pendingStore.noteReachableForegroundStarted(at: now)
        pendingStore.updateReachableForegroundTimeouts(now: now)
        refreshPendingState()
        retryPendingSubmissionsIfPossible()
    }

    @MainActor
    private func retryPendingSubmissionsIfPossible() {
        guard isRetryingPendingSubmissions == false,
              isAppActive,
              let session,
              session.activationState == .activated,
              session.isReachable else {
            return
        }

        let submissions = (
            pendingStore.retryableSubmissions()
                + pendingStore.needsUserActionResultQuerySubmissions()
        )
        .sorted { left, right in
            if left.createdAt == right.createdAt {
                return left.clientSubmissionID < right.clientSubmissionID
            }

            return left.createdAt < right.createdAt
        }
        guard submissions.isEmpty == false else {
            return
        }

        isRetryingPendingSubmissions = true
        pendingRetryTask?.cancel()
        pendingRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRetryingPendingSubmissions = false }

            for submission in submissions {
                if Task.isCancelled {
                    break
                }

                do {
                    _ = try await self.sendPendingSubmission(
                        submission,
                        using: session,
                        marksSyncing: submission.status != .needsUserAction
                    )
                } catch let error as SetSubmissionError {
                    if case .rejected = error {
                        continue
                    }

                    self.restoreSubmissionAfterRetryFailure(submission)
                } catch {
                    self.restoreSubmissionAfterRetryFailure(submission)
                }
            }
        }
    }

    @MainActor
    private func restoreSubmissionAfterRetryFailure(_ submission: WatchPendingSetSubmission) {
        let now = Date().timeIntervalSince1970

        if submission.status == .needsUserAction {
            pendingStore.markNeedsUserAction(
                clientSubmissionID: submission.clientSubmissionID,
                now: now,
                reason: submission.manualReviewReason
            )
        } else {
            pendingStore.markPending(
                clientSubmissionID: submission.clientSubmissionID,
                now: now
            )
        }

        refreshPendingState()
    }

    @MainActor
    private func refreshPendingState() {
        pendingSubmissionCount = pendingStore.activeSubmissionCount
        needsUserActionSubmissionCount = pendingStore.needsUserActionCount
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if error != nil {
            updateConnectionStatus(.failed)
            return
        }

        updateReachability(for: session)
        applyMessage(session.receivedApplicationContext)
        requestTrainingState()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateReachability(for: session) { [weak self] previousStatus, nextStatus in
            guard previousStatus == .unreachable, nextStatus == .reachable else {
                return
            }

            self?.requestTrainingState()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyMessage(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        applyMessage(message)
        replyHandler([:])
    }
}

extension WatchSessionManager {
    static func preview(
        connectionStatus: ConnectionStatus,
        isTraining: Bool?,
        snapshot: WatchWorkoutSnapshot? = nil,
        isCachedSnapshot: Bool = false
    ) -> WatchSessionManager {
        WatchSessionManager(
            session: nil,
            connectionStatus: connectionStatus,
            isTraining: isTraining,
            snapshot: snapshot,
            isCachedSnapshot: isCachedSnapshot
        )
    }

    private static func cachedSnapshot(in userDefaults: UserDefaults) -> WatchWorkoutSnapshot? {
        guard let propertyList = userDefaults.dictionary(forKey: cachedSnapshotKey) else {
            return nil
        }

        return try? WatchWorkoutSnapshot(propertyList: propertyList)
    }

    private func cache(_ snapshot: WatchWorkoutSnapshot) {
        userDefaults.set(snapshot.propertyList, forKey: Self.cachedSnapshotKey)
    }

    private func clearCachedSnapshot() {
        userDefaults.removeObject(forKey: Self.cachedSnapshotKey)
    }
}
