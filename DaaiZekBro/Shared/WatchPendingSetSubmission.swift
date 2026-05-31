import Foundation

struct WatchPendingSetSubmission: Equatable {
    nonisolated static let schemaVersion = 1

    enum Status: String, CaseIterable {
        case pending
        case syncing
        case synced
        case needsUserAction
        case discarded

        nonisolated var countsTowardSnapshot: Bool {
            switch self {
            case .pending, .syncing, .synced:
                true
            case .needsUserAction, .discarded:
                false
            }
        }

        nonisolated var canTimeoutFromReachableForeground: Bool {
            switch self {
            case .pending, .syncing:
                true
            case .synced, .needsUserAction, .discarded:
                false
            }
        }
    }

    enum ParseError: Error, Equatable {
        case invalidSchemaVersion
        case invalidSubmission
        case invalidStatus
        case invalidCreatedAt
        case invalidUpdatedAt
        case invalidReachableForegroundStartedAt
        case invalidSyncedAt
        case invalidSavedSetIndex
        case invalidCompletedSetCount
        case invalidManualReviewReason
    }

    let submission: WatchSetSubmissionMessage
    var status: Status
    let createdAt: TimeInterval
    var updatedAt: TimeInterval
    var reachableForegroundStartedAt: TimeInterval?
    var syncedAt: TimeInterval?
    var savedSetIndex: Int?
    var completedSetCount: Int?
    var manualReviewReason: WatchSetSubmissionManualReviewReason?

    nonisolated var clientSubmissionID: String {
        submission.clientSubmissionID
    }

    nonisolated var propertyList: [String: Any] {
        var propertyList: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "submission": submission.propertyList,
            "status": status.rawValue,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
        ]

        if let reachableForegroundStartedAt {
            propertyList["reachableForegroundStartedAt"] = reachableForegroundStartedAt
        }

        if let syncedAt {
            propertyList["syncedAt"] = syncedAt
        }

        if let savedSetIndex {
            propertyList["savedSetIndex"] = savedSetIndex
        }

        if let completedSetCount {
            propertyList["completedSetCount"] = completedSetCount
        }

        if let manualReviewReason {
            propertyList["manualReviewReason"] = manualReviewReason.rawValue
        }

        return propertyList
    }

    nonisolated init(
        submission: WatchSetSubmissionMessage,
        status: Status = .pending,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        reachableForegroundStartedAt: TimeInterval? = nil,
        syncedAt: TimeInterval? = nil,
        savedSetIndex: Int? = nil,
        completedSetCount: Int? = nil,
        manualReviewReason: WatchSetSubmissionManualReviewReason? = nil
    ) {
        self.submission = submission
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reachableForegroundStartedAt = reachableForegroundStartedAt
        self.syncedAt = syncedAt
        self.savedSetIndex = savedSetIndex
        self.completedSetCount = completedSetCount
        self.manualReviewReason = manualReviewReason
    }

    nonisolated init(propertyList: [String: Any]) throws {
        guard let schemaVersion = propertyList["schemaVersion"] as? Int,
              schemaVersion == Self.schemaVersion else {
            throw ParseError.invalidSchemaVersion
        }

        guard let submissionPropertyList = propertyList["submission"] as? [String: Any] else {
            throw ParseError.invalidSubmission
        }

        let submission: WatchSetSubmissionMessage
        do {
            submission = try WatchSetSubmissionMessage(propertyList: submissionPropertyList)
        } catch {
            throw ParseError.invalidSubmission
        }

        guard let statusValue = propertyList["status"] as? String,
              let status = Status(rawValue: statusValue) else {
            throw ParseError.invalidStatus
        }

        guard let createdAt = propertyList["createdAt"] as? TimeInterval,
              createdAt.isFinite else {
            throw ParseError.invalidCreatedAt
        }

        guard let updatedAt = propertyList["updatedAt"] as? TimeInterval,
              updatedAt.isFinite else {
            throw ParseError.invalidUpdatedAt
        }

        let reachableForegroundStartedAt: TimeInterval?
        if let value = propertyList["reachableForegroundStartedAt"] {
            guard let parsed = value as? TimeInterval,
                  parsed.isFinite else {
                throw ParseError.invalidReachableForegroundStartedAt
            }
            reachableForegroundStartedAt = parsed
        } else {
            reachableForegroundStartedAt = nil
        }

        let syncedAt: TimeInterval?
        if let value = propertyList["syncedAt"] {
            guard let parsed = value as? TimeInterval,
                  parsed.isFinite else {
                throw ParseError.invalidSyncedAt
            }
            syncedAt = parsed
        } else {
            syncedAt = nil
        }

        let savedSetIndex: Int?
        if let value = propertyList["savedSetIndex"] {
            guard let parsed = value as? Int,
                  parsed >= 1 else {
                throw ParseError.invalidSavedSetIndex
            }
            savedSetIndex = parsed
        } else {
            savedSetIndex = nil
        }

        let completedSetCount: Int?
        if let value = propertyList["completedSetCount"] {
            guard let parsed = value as? Int,
                  parsed >= 1 else {
                throw ParseError.invalidCompletedSetCount
            }
            completedSetCount = parsed
        } else {
            completedSetCount = nil
        }

        let manualReviewReason: WatchSetSubmissionManualReviewReason?
        if let value = propertyList["manualReviewReason"] {
            guard let parsed = value as? String,
                  let reason = WatchSetSubmissionManualReviewReason(rawValue: parsed) else {
                throw ParseError.invalidManualReviewReason
            }
            manualReviewReason = reason
        } else {
            manualReviewReason = nil
        }

        self.submission = submission
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reachableForegroundStartedAt = reachableForegroundStartedAt
        self.syncedAt = syncedAt
        self.savedSetIndex = savedSetIndex
        self.completedSetCount = completedSetCount
        self.manualReviewReason = manualReviewReason
    }

    nonisolated func isIncluded(in snapshot: WatchWorkoutSnapshot) -> Bool {
        guard status == .synced,
              submission.sessionID == snapshot.sessionID,
              let completedSetCount,
              let exercise = snapshot.exercises.first(where: { $0.exerciseOrderIndex == submission.exerciseOrderIndex }),
              exercise.completedSetCount >= completedSetCount else {
            return false
        }

        guard let side = submission.side else {
            return true
        }

        guard let savedSetIndex else {
            return false
        }

        switch side {
        case "left":
            return exercise.leftCompletedSetCount >= savedSetIndex
        case "right":
            return exercise.rightCompletedSetCount >= savedSetIndex
        default:
            return false
        }
    }

    nonisolated func shouldOverlay(on snapshot: WatchWorkoutSnapshot) -> Bool {
        guard submission.sessionID == snapshot.sessionID else {
            return false
        }

        switch status {
        case .pending, .syncing:
            return true
        case .synced:
            return isIncluded(in: snapshot) == false
        case .needsUserAction, .discarded:
            return false
        }
    }
}

final class WatchPendingSetSubmissionStore {
    static let defaultKey = "WatchPendingSetSubmissionStore.submissions"
    static let reachableForegroundTimeout: TimeInterval = 120

    private let userDefaults: UserDefaults
    private let key: String
    private var queuedSubmissions: [WatchPendingSetSubmission]

    var submissions: [WatchPendingSetSubmission] {
        queuedSubmissions
    }

    var activeSubmissionCount: Int {
        queuedSubmissions.filter { submission in
            submission.status == .pending || submission.status == .syncing
        }.count
    }

    var needsUserActionCount: Int {
        queuedSubmissions.filter { $0.status == .needsUserAction }.count
    }

    init(
        userDefaults: UserDefaults = .standard,
        key: String = WatchPendingSetSubmissionStore.defaultKey
    ) {
        self.userDefaults = userDefaults
        self.key = key
        queuedSubmissions = Self.loadSubmissions(from: userDefaults, key: key)
    }

    @discardableResult
    func enqueue(
        draft: WatchRecordDraft,
        snapshot: WatchWorkoutSnapshot,
        exercise: WatchWorkoutSnapshot.Exercise,
        now: Date,
        clientSubmissionID: () -> String = { UUID().uuidString }
    ) throws -> WatchPendingSetSubmission {
        try enqueue(
            draft: draft,
            sessionID: snapshot.sessionID,
            sessionName: snapshot.sessionName,
            sessionStartedAt: snapshot.startedAt,
            exercise: exercise,
            now: now,
            clientSubmissionID: clientSubmissionID
        )
    }

    @discardableResult
    func enqueue(
        draft: WatchRecordDraft,
        sessionID: String,
        sessionName: String? = nil,
        sessionStartedAt: TimeInterval? = nil,
        exercise: WatchWorkoutSnapshot.Exercise,
        now: Date,
        clientSubmissionID: () -> String = { UUID().uuidString }
    ) throws -> WatchPendingSetSubmission {
        guard draft.canSubmit(isUnilateral: exercise.isUnilateral) else {
            throw WatchSessionPendingSubmissionError.invalidDraft
        }

        let timestamp = now.timeIntervalSince1970
        let id = clientSubmissionID()
        let message = WatchSetSubmissionMessage(
            clientSubmissionID: id,
            sentAt: timestamp,
            sessionID: sessionID,
            sessionName: sessionName,
            sessionStartedAt: sessionStartedAt,
            exerciseOrderIndex: exercise.exerciseOrderIndex,
            exerciseName: exercise.name,
            weight: draft.weight,
            weightUnit: exercise.weightUnit,
            reps: draft.reps,
            rpe: draft.rpe,
            side: draft.side,
            completedAt: timestamp
        )
        let pending = WatchPendingSetSubmission(
            submission: message,
            status: .pending,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        upsert(pending)
        return pending
    }

    func replaceAll(_ submissions: [WatchPendingSetSubmission]) {
        queuedSubmissions = submissions
        save()
    }

    func submission(clientSubmissionID: String) -> WatchPendingSetSubmission? {
        queuedSubmissions.first { $0.clientSubmissionID == clientSubmissionID }
    }

    func markPending(clientSubmissionID: String, now: TimeInterval) {
        update(clientSubmissionID: clientSubmissionID, now: now) { submission in
            submission.status = .pending
        }
    }

    func markSyncing(clientSubmissionID: String, now: TimeInterval) {
        update(clientSubmissionID: clientSubmissionID, now: now) { submission in
            submission.status = .syncing
        }
    }

    func markSynced(
        clientSubmissionID: String,
        now: TimeInterval,
        savedSetIndex: Int,
        completedSetCount: Int
    ) {
        update(clientSubmissionID: clientSubmissionID, now: now) { submission in
            submission.status = .synced
            submission.reachableForegroundStartedAt = nil
            submission.syncedAt = now
            submission.savedSetIndex = savedSetIndex
            submission.completedSetCount = completedSetCount
        }
    }

    func markNeedsUserAction(
        clientSubmissionID: String,
        now: TimeInterval,
        reason: WatchSetSubmissionManualReviewReason? = nil
    ) {
        update(clientSubmissionID: clientSubmissionID, now: now) { submission in
            submission.status = .needsUserAction
            submission.reachableForegroundStartedAt = nil
            if let reason {
                submission.manualReviewReason = reason
            }
        }
    }

    func discard(clientSubmissionID: String, now: TimeInterval) {
        update(clientSubmissionID: clientSubmissionID, now: now) { submission in
            submission.status = .discarded
            submission.reachableForegroundStartedAt = nil
        }
    }

    func noteReachableForegroundStarted(at now: TimeInterval) {
        var changed = false

        for index in queuedSubmissions.indices {
            guard queuedSubmissions[index].status.canTimeoutFromReachableForeground,
                  queuedSubmissions[index].reachableForegroundStartedAt == nil else {
                continue
            }

            queuedSubmissions[index].reachableForegroundStartedAt = now
            queuedSubmissions[index].updatedAt = now
            changed = true
        }

        if changed {
            save()
        }
    }

    func clearReachableForegroundTimers() {
        var changed = false

        for index in queuedSubmissions.indices {
            guard queuedSubmissions[index].reachableForegroundStartedAt != nil else {
                continue
            }

            queuedSubmissions[index].reachableForegroundStartedAt = nil
            changed = true
        }

        if changed {
            save()
        }
    }

    func retryableSubmissions() -> [WatchPendingSetSubmission] {
        queuedSubmissions.filter { submission in
            submission.status == .pending || submission.status == .syncing
        }
    }

    func needsUserActionResultQuerySubmissions() -> [WatchPendingSetSubmission] {
        queuedSubmissions.filter { $0.status == .needsUserAction }
    }

    @discardableResult
    func updateReachableForegroundTimeouts(
        now: TimeInterval,
        timeout: TimeInterval = WatchPendingSetSubmissionStore.reachableForegroundTimeout
    ) -> [WatchPendingSetSubmission] {
        var changed = false
        var timedOutSubmissions: [WatchPendingSetSubmission] = []

        for index in queuedSubmissions.indices {
            guard queuedSubmissions[index].status.canTimeoutFromReachableForeground,
                  let startedAt = queuedSubmissions[index].reachableForegroundStartedAt,
                  now - startedAt >= timeout else {
                continue
            }

            queuedSubmissions[index].status = .needsUserAction
            queuedSubmissions[index].updatedAt = now
            queuedSubmissions[index].reachableForegroundStartedAt = nil
            queuedSubmissions[index].manualReviewReason = .syncTimeout
            timedOutSubmissions.append(queuedSubmissions[index])
            changed = true
        }

        if changed {
            save()
        }

        return timedOutSubmissions
    }

    func removeSyncedSubmissions(includedIn snapshot: WatchWorkoutSnapshot) {
        let originalCount = queuedSubmissions.count
        queuedSubmissions.removeAll { submission in
            submission.isIncluded(in: snapshot)
        }

        if queuedSubmissions.count != originalCount {
            save()
        }
    }

    func remove(clientSubmissionID: String) {
        let originalCount = queuedSubmissions.count
        queuedSubmissions.removeAll { $0.clientSubmissionID == clientSubmissionID }

        if queuedSubmissions.count != originalCount {
            save()
        }
    }

    private func upsert(_ submission: WatchPendingSetSubmission) {
        if let index = queuedSubmissions.firstIndex(where: { $0.clientSubmissionID == submission.clientSubmissionID }) {
            queuedSubmissions[index] = submission
        } else {
            queuedSubmissions.append(submission)
        }

        save()
    }

    private func update(
        clientSubmissionID: String,
        now: TimeInterval,
        apply: (inout WatchPendingSetSubmission) -> Void
    ) {
        guard let index = queuedSubmissions.firstIndex(where: { $0.clientSubmissionID == clientSubmissionID }) else {
            return
        }

        apply(&queuedSubmissions[index])
        queuedSubmissions[index].updatedAt = now
        save()
    }

    private func save() {
        userDefaults.set(queuedSubmissions.map(\.propertyList), forKey: key)
    }

    private static func loadSubmissions(from userDefaults: UserDefaults, key: String) -> [WatchPendingSetSubmission] {
        guard let propertyLists = userDefaults.array(forKey: key) as? [[String: Any]] else {
            return []
        }

        return propertyLists.compactMap { try? WatchPendingSetSubmission(propertyList: $0) }
    }
}

enum WatchSessionPendingSubmissionError: Error, Equatable {
    case invalidDraft
}

extension WatchWorkoutSnapshot {
    nonisolated func applyingPendingSetSubmissions(
        _ submissions: [WatchPendingSetSubmission]
    ) -> WatchWorkoutSnapshot {
        let activeSubmissions = submissions
            .filter { pending in
                pending.status.countsTowardSnapshot && pending.shouldOverlay(on: self)
            }
            .sorted { left, right in
                if left.submission.completedAt == right.submission.completedAt {
                    return left.createdAt < right.createdAt
                }

                return left.submission.completedAt < right.submission.completedAt
            }

        guard activeSubmissions.isEmpty == false else {
            return self
        }

        let updatedExercises = exercises.map { exercise in
            let matchingSubmissions = activeSubmissions.filter {
                $0.submission.exerciseOrderIndex == exercise.exerciseOrderIndex
            }

            guard matchingSubmissions.isEmpty == false else {
                return exercise
            }

            let leftCount = matchingSubmissions.reduce(exercise.leftCompletedSetCount) { count, pending in
                count + (pending.submission.side == "left" ? 1 : 0)
            }
            let rightCount = matchingSubmissions.reduce(exercise.rightCompletedSetCount) { count, pending in
                count + (pending.submission.side == "right" ? 1 : 0)
            }
            let lastSubmission = matchingSubmissions.last?.submission

            return WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: exercise.exerciseOrderIndex,
                name: exercise.name,
                completedSetCount: exercise.completedSetCount + matchingSubmissions.count,
                weightUnit: exercise.weightUnit,
                isUnilateral: exercise.isUnilateral,
                defaultRestSeconds: exercise.defaultRestSeconds,
                leftCompletedSetCount: leftCount,
                rightCompletedSetCount: rightCount,
                lastSetReference: lastSubmission.map {
                    WatchWorkoutSnapshot.LastSetReference(
                        weight: $0.weight,
                        reps: $0.reps,
                        source: "currentSession"
                    )
                } ?? exercise.lastSetReference
            )
        }

        return WatchWorkoutSnapshot(
            sessionID: sessionID,
            sessionName: sessionName,
            startedAt: startedAt,
            exercises: updatedExercises
        )
    }
}
