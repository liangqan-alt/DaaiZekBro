import Foundation
import SwiftData

@MainActor
struct PhoneTrainingStateSource {
    var isTraining: @MainActor (ModelContext) throws -> Bool
    var currentSnapshot: @MainActor (ModelContext) throws -> WatchWorkoutSnapshot?

    init(
        _ isTraining: @escaping @MainActor (ModelContext) throws -> Bool,
        currentSnapshot: @escaping @MainActor (ModelContext) throws -> WatchWorkoutSnapshot? = { _ in nil }
    ) {
        self.isTraining = isTraining
        self.currentSnapshot = currentSnapshot
    }

    init(currentSnapshot: @escaping @MainActor (ModelContext) throws -> WatchWorkoutSnapshot?) {
        self.currentSnapshot = currentSnapshot
        isTraining = { context in
            try currentSnapshot(context) != nil
        }
    }

    static let live = PhoneTrainingStateSource(
        { context in
            try WorkoutSessionLifecycle.currentOpenSession(in: context) != nil
        },
        currentSnapshot: currentWorkoutSnapshot
    )

    private static func currentWorkoutSnapshot(in context: ModelContext) throws -> WatchWorkoutSnapshot? {
        guard let session = try WorkoutSessionLifecycle.currentOpenSession(in: context) else {
            return nil
        }

        let sessionID = session.id
        let completedSetCounts = try completedSetCounts(sessionID: sessionID, in: context)
        let exercises = try snapshotExercises(
            for: session,
            completedSetCounts: completedSetCounts,
            in: context
        )

        return WatchWorkoutSnapshot(
            sessionID: sessionID.uuidString,
            sessionName: sessionName(for: session),
            startedAt: session.startedAt.timeIntervalSince1970,
            exercises: exercises
        )
    }

    private static func sessionName(for session: WorkoutSession) -> String {
        if let templateName = session.template?.name, templateName.isEmpty == false {
            return templateName
        }

        return session.templateNameSnapshot.isEmpty ? "未命名训练" : session.templateNameSnapshot
    }

    private static func snapshotExercises(
        for session: WorkoutSession,
        completedSetCounts: [Int: Int],
        in context: ModelContext
    ) throws -> [WatchWorkoutSnapshot.Exercise] {
        let snapshots = try exerciseSnapshots(sessionID: session.id, in: context)

        if snapshots.isEmpty {
            return try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context)
                .map { exercise in
                    WatchWorkoutSnapshot.Exercise(
                        exerciseOrderIndex: exercise.orderIndex,
                        name: exercise.name,
                        completedSetCount: completedSetCounts[exercise.orderIndex, default: 0],
                        weightUnit: exercise.weightUnit.rawValue,
                        isUnilateral: exercise.isUnilateral,
                        defaultRestSeconds: exercise.defaultRestSeconds
                    )
                }
        }

        return snapshots.map { snapshot in
            WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: snapshot.orderIndex,
                name: snapshot.exerciseNameSnapshot,
                completedSetCount: completedSetCounts[snapshot.orderIndex, default: 0],
                weightUnit: snapshot.weightUnit.rawValue,
                isUnilateral: snapshot.isUnilateralSnapshot,
                defaultRestSeconds: snapshot.defaultRestSecondsSnapshot
            )
        }
    }

    private static func exerciseSnapshots(
        sessionID: UUID,
        in context: ModelContext
    ) throws -> [WorkoutSessionExerciseSnapshot] {
        try context.fetch(
            FetchDescriptor<WorkoutSessionExerciseSnapshot>(
                predicate: #Predicate<WorkoutSessionExerciseSnapshot> { snapshot in
                    snapshot.session?.id == sessionID
                },
                sortBy: [
                    SortDescriptor(\WorkoutSessionExerciseSnapshot.orderIndex),
                    SortDescriptor(\WorkoutSessionExerciseSnapshot.exerciseNameSnapshot),
                ]
            )
        )
    }

    private static func completedSetCounts(sessionID: UUID, in context: ModelContext) throws -> [Int: Int] {
        let sets = try context.fetch(
            FetchDescriptor<WorkoutSet>(
                predicate: #Predicate<WorkoutSet> { set in
                    set.session?.id == sessionID
                }
            )
        )
        var counts: [Int: Int] = [:]

        for set in sets {
            counts[set.exerciseOrderIndex, default: 0] += 1
        }

        return counts
    }
}
