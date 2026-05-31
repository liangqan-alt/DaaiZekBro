import Foundation
import Testing
@testable import DaaiZekBro

@MainActor
struct WatchPendingSubmissionQueueTests {
    @Test func pendingSubmissionRoundTripsThroughPropertyListAndUserDefaults() throws {
        let syncedSubmission = makePendingSubmission(
            clientSubmissionID: "synced-1",
            status: .synced,
            savedSetIndex: 2,
            completedSetCount: 4,
            syncedAt: 1_800_000_201
        )
        let needsUserActionSubmission = makePendingSubmission(
            clientSubmissionID: "needs-action-1",
            status: .needsUserAction,
            manualReviewReason: .syncTimeout
        )

        let decoded = try WatchPendingSetSubmission(propertyList: syncedSubmission.propertyList)

        #expect(decoded == syncedSubmission)

        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        store.replaceAll([syncedSubmission, needsUserActionSubmission])

        let restoredStore = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        #expect(restoredStore.submissions == [syncedSubmission, needsUserActionSubmission])
    }

    @Test func enqueueGeneratesClientSubmissionIDOnceAndStatusChangesReuseIt() throws {
        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        let exercise = makeSnapshotExercise(orderIndex: 0, name: "Bench Press", isUnilateral: false)
        let draft = WatchRecordDraft(weight: 80, reps: 8, rpe: nil, side: nil)

        let queued = try store.enqueue(
            draft: draft,
            sessionID: "00000000-0000-0000-0000-000000000111",
            exercise: exercise,
            now: Date(timeIntervalSince1970: 1_800_000_100),
            clientSubmissionID: { "generated-once" }
        )

        store.markSyncing(clientSubmissionID: queued.clientSubmissionID, now: 1_800_000_101)
        store.markPending(clientSubmissionID: queued.clientSubmissionID, now: 1_800_000_102)

        let restored = try #require(store.submission(clientSubmissionID: queued.clientSubmissionID))
        #expect(restored.clientSubmissionID == "generated-once")
        #expect(restored.submission.clientSubmissionID == "generated-once")
        #expect(restored.submission.propertyList["clientSubmissionID"] as? String == "generated-once")
    }

    @Test func enqueueFromSnapshotCarriesSessionDisplayFields() throws {
        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        let exercise = makeSnapshotExercise(orderIndex: 0, name: "Bench Press", isUnilateral: false)
        let snapshot = WatchWorkoutSnapshot(
            sessionID: "00000000-0000-0000-0000-000000000111",
            sessionName: "Push A",
            startedAt: 1_800_000_000,
            exercises: [exercise]
        )

        let queued = try store.enqueue(
            draft: WatchRecordDraft(weight: 80, reps: 8, rpe: nil, side: nil),
            snapshot: snapshot,
            exercise: exercise,
            now: Date(timeIntervalSince1970: 1_800_000_100),
            clientSubmissionID: { "snapshot-submit-1" }
        )

        #expect(queued.submission.sessionName == "Push A")
        #expect(queued.submission.sessionStartedAt == 1_800_000_000)
    }

    @Test func pendingOverlayAddsCompletedCountsAndSideCounts() {
        let snapshot = WatchWorkoutSnapshot(
            sessionID: "00000000-0000-0000-0000-000000000111",
            sessionName: "Push A",
            startedAt: 1_800_000_000,
            exercises: [
                makeSnapshotExercise(
                    orderIndex: 0,
                    name: "Lateral Raise",
                    completedSetCount: 2,
                    leftCompletedSetCount: 1,
                    rightCompletedSetCount: 1,
                    isUnilateral: true
                ),
            ]
        )
        let activeLeft = makePendingSubmission(clientSubmissionID: "pending-left", status: .pending, side: "left")
        let activeRight = makePendingSubmission(clientSubmissionID: "syncing-right", status: .syncing, side: "right")
        let needsAction = makePendingSubmission(clientSubmissionID: "needs-action", status: .needsUserAction, side: "left")
        let discarded = makePendingSubmission(clientSubmissionID: "discarded", status: .discarded, side: "right")

        let overlaid = snapshot.applyingPendingSetSubmissions([
            activeLeft,
            activeRight,
            needsAction,
            discarded,
        ])

        let exercise = overlaid.exercises[0]
        #expect(exercise.completedSetCount == 4)
        #expect(exercise.leftCompletedSetCount == 2)
        #expect(exercise.rightCompletedSetCount == 2)
    }

    @Test func syncedSubmissionOverlaysStaleSnapshotUntilLiveSnapshotCatchesUp() {
        let staleSnapshot = WatchWorkoutSnapshot(
            sessionID: "00000000-0000-0000-0000-000000000111",
            sessionName: "Push A",
            startedAt: 1_800_000_000,
            exercises: [
                makeSnapshotExercise(
                    orderIndex: 0,
                    name: "Bench Press",
                    completedSetCount: 2
                ),
            ]
        )
        let caughtUpSnapshot = WatchWorkoutSnapshot(
            sessionID: "00000000-0000-0000-0000-000000000111",
            sessionName: "Push A",
            startedAt: 1_800_000_000,
            exercises: [
                makeSnapshotExercise(
                    orderIndex: 0,
                    name: "Bench Press",
                    completedSetCount: 3
                ),
            ]
        )
        let synced = makePendingSubmission(
            clientSubmissionID: "synced",
            status: .synced,
            savedSetIndex: 3,
            completedSetCount: 3
        )

        #expect(staleSnapshot.applyingPendingSetSubmissions([synced]).exercises[0].completedSetCount == 3)
        #expect(caughtUpSnapshot.applyingPendingSetSubmissions([synced]) == caughtUpSnapshot)
    }

    @Test func pendingOverlayIgnoresOtherSessionsAndExercises() {
        let snapshot = WatchWorkoutSnapshot(
            sessionID: "00000000-0000-0000-0000-000000000111",
            sessionName: "Push A",
            startedAt: 1_800_000_000,
            exercises: [
                makeSnapshotExercise(orderIndex: 0, name: "Bench Press", completedSetCount: 1),
            ]
        )
        let otherSession = makePendingSubmission(
            clientSubmissionID: "other-session",
            sessionID: "00000000-0000-0000-0000-000000000222"
        )
        let otherExercise = makePendingSubmission(
            clientSubmissionID: "other-exercise",
            exerciseOrderIndex: 1
        )

        let overlaid = snapshot.applyingPendingSetSubmissions([otherSession, otherExercise])

        #expect(overlaid == snapshot)
    }

    @Test func reachableForegroundTimeoutStartsAtReachableForegroundBoundary() throws {
        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        store.replaceAll([
            makePendingSubmission(clientSubmissionID: "pending-1", status: .pending),
            makePendingSubmission(clientSubmissionID: "syncing-1", status: .syncing),
        ])

        store.noteReachableForegroundStarted(at: 1_800_000_000)
        store.updateReachableForegroundTimeouts(now: 1_800_000_119)

        #expect(store.submission(clientSubmissionID: "pending-1")?.status == .pending)
        #expect(store.submission(clientSubmissionID: "syncing-1")?.status == .syncing)

        store.updateReachableForegroundTimeouts(now: 1_800_000_120)

        #expect(store.submission(clientSubmissionID: "pending-1")?.status == .needsUserAction)
        #expect(store.submission(clientSubmissionID: "syncing-1")?.status == .needsUserAction)
        #expect(store.submission(clientSubmissionID: "pending-1")?.manualReviewReason == .syncTimeout)
        #expect(store.submission(clientSubmissionID: "syncing-1")?.manualReviewReason == .syncTimeout)
    }

    @Test func syncedSubmissionsAreRemovedOnlyAfterSnapshotIncludesAckedSet() throws {
        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        let covered = makePendingSubmission(
            clientSubmissionID: "covered",
            status: .synced,
            side: "left",
            savedSetIndex: 2,
            completedSetCount: 3
        )
        let notYetCovered = makePendingSubmission(
            clientSubmissionID: "not-yet-covered",
            status: .synced,
            side: "right",
            savedSetIndex: 2,
            completedSetCount: 4
        )
        let pending = makePendingSubmission(clientSubmissionID: "pending")
        store.replaceAll([covered, notYetCovered, pending])
        let snapshot = WatchWorkoutSnapshot(
            sessionID: "00000000-0000-0000-0000-000000000111",
            sessionName: "Push A",
            startedAt: 1_800_000_000,
            exercises: [
                makeSnapshotExercise(
                    orderIndex: 0,
                    name: "Lateral Raise",
                    completedSetCount: 3,
                    leftCompletedSetCount: 2,
                    rightCompletedSetCount: 1,
                    isUnilateral: true
                ),
            ]
        )

        store.removeSyncedSubmissions(includedIn: snapshot)

        #expect(store.submission(clientSubmissionID: "covered") == nil)
        #expect(store.submission(clientSubmissionID: "not-yet-covered") == notYetCovered)
        #expect(store.submission(clientSubmissionID: "pending") == pending)
    }

    @Test func syncedSubmissionsDoNotCountAsActivePending() throws {
        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        store.replaceAll([
            makePendingSubmission(clientSubmissionID: "pending", status: .pending),
            makePendingSubmission(clientSubmissionID: "syncing", status: .syncing),
            makePendingSubmission(
                clientSubmissionID: "synced",
                status: .synced,
                savedSetIndex: 2,
                completedSetCount: 2
            ),
        ])

        #expect(store.activeSubmissionCount == 2)
    }

    @Test func needsUserActionIsExcludedFromOverlayButReturnedForResultQuery() throws {
        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        let pending = makePendingSubmission(clientSubmissionID: "pending", status: .pending)
        let needsAction = makePendingSubmission(
            clientSubmissionID: "needs-action",
            status: .needsUserAction,
            side: "left",
            manualReviewReason: .syncTimeout
        )
        let snapshot = WatchWorkoutSnapshot(
            sessionID: "00000000-0000-0000-0000-000000000111",
            sessionName: "Push A",
            startedAt: 1_800_000_000,
            exercises: [
                makeSnapshotExercise(
                    orderIndex: 0,
                    name: "Lateral Raise",
                    completedSetCount: 2,
                    leftCompletedSetCount: 1,
                    rightCompletedSetCount: 1,
                    isUnilateral: true
                ),
            ]
        )
        store.replaceAll([
            pending,
            needsAction,
            makePendingSubmission(clientSubmissionID: "synced", status: .synced, savedSetIndex: 3, completedSetCount: 3),
            makePendingSubmission(clientSubmissionID: "discarded", status: .discarded),
        ])

        let overlaid = snapshot.applyingPendingSetSubmissions([needsAction])
        #expect(overlaid == snapshot)
        #expect(store.needsUserActionResultQuerySubmissions() == [needsAction])
    }

    @Test func reachableForegroundTimeoutDoesNotResetWhileStillWaiting() throws {
        let userDefaults = try makeUserDefaults()
        let store = WatchPendingSetSubmissionStore(userDefaults: userDefaults, key: "queue")
        store.replaceAll([makePendingSubmission(clientSubmissionID: "pending-1", status: .pending)])

        store.noteReachableForegroundStarted(at: 1_800_000_000)
        store.noteReachableForegroundStarted(at: 1_800_000_060)
        store.updateReachableForegroundTimeouts(now: 1_800_000_119)

        #expect(store.submission(clientSubmissionID: "pending-1")?.status == .pending)

        store.updateReachableForegroundTimeouts(now: 1_800_000_120)

        #expect(store.submission(clientSubmissionID: "pending-1")?.status == .needsUserAction)
    }
}

private func makePendingSubmission(
    clientSubmissionID: String,
    status: WatchPendingSetSubmission.Status = .pending,
    sessionID: String = "00000000-0000-0000-0000-000000000111",
    exerciseOrderIndex: Int = 0,
    side: String? = nil,
    reachableForegroundStartedAt: TimeInterval? = nil,
    savedSetIndex: Int? = nil,
    completedSetCount: Int? = nil,
    syncedAt: TimeInterval? = nil,
    manualReviewReason: WatchSetSubmissionManualReviewReason? = nil
) -> WatchPendingSetSubmission {
    WatchPendingSetSubmission(
        submission: WatchSetSubmissionMessage(
            clientSubmissionID: clientSubmissionID,
            sentAt: 1_800_000_100,
            sessionID: sessionID,
            exerciseOrderIndex: exerciseOrderIndex,
            exerciseName: "Lateral Raise",
            weight: 10,
            weightUnit: "kg",
            reps: 12,
            rpe: 8,
            side: side,
            completedAt: 1_800_000_101
        ),
        status: status,
        createdAt: 1_800_000_100,
        updatedAt: 1_800_000_101,
        reachableForegroundStartedAt: reachableForegroundStartedAt,
        syncedAt: syncedAt,
        savedSetIndex: savedSetIndex,
        completedSetCount: completedSetCount,
        manualReviewReason: manualReviewReason
    )
}

private func makeSnapshotExercise(
    orderIndex: Int,
    name: String,
    completedSetCount: Int = 0,
    leftCompletedSetCount: Int = 0,
    rightCompletedSetCount: Int = 0,
    isUnilateral: Bool = false
) -> WatchWorkoutSnapshot.Exercise {
    WatchWorkoutSnapshot.Exercise(
        exerciseOrderIndex: orderIndex,
        name: name,
        completedSetCount: completedSetCount,
        weightUnit: "kg",
        isUnilateral: isUnilateral,
        defaultRestSeconds: 120,
        leftCompletedSetCount: leftCompletedSetCount,
        rightCompletedSetCount: rightCompletedSetCount
    )
}

private func makeUserDefaults() throws -> UserDefaults {
    let suiteName = "WatchPendingSubmissionQueueTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
}
