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

    private static let historyReferencePageSize = 50
    private static let historyReferenceMaxPages = 4

    private static func currentWorkoutSnapshot(in context: ModelContext) throws -> WatchWorkoutSnapshot? {
        guard let session = try WorkoutSessionLifecycle.currentOpenSession(in: context) else {
            return nil
        }

        let sessionSets = try setsForSession(sessionID: session.id, in: context)
        let exercises = try snapshotExercises(
            for: session,
            sessionSets: sessionSets,
            in: context
        )

        return WatchWorkoutSnapshot(
            sessionID: session.id.uuidString,
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
        sessionSets: [WorkoutSet],
        in context: ModelContext
    ) throws -> [WatchWorkoutSnapshot.Exercise] {
        let snapshots = try exerciseSnapshots(sessionID: session.id, in: context)
        let descriptors: [WorkoutSessionExerciseDescriptor]

        if snapshots.isEmpty {
            descriptors = try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context)
        } else {
            descriptors = snapshots.map { snapshot in
                WorkoutSessionExerciseDescriptor(
                    exercise: snapshot.exercise,
                    name: snapshot.exerciseNameSnapshot,
                    defaultRestSeconds: snapshot.defaultRestSecondsSnapshot,
                    isUnilateral: snapshot.isUnilateralSnapshot,
                    weightUnit: snapshot.weightUnit,
                    orderIndex: snapshot.orderIndex
                )
            }
        }

        return try descriptors.map { descriptor in
            let exerciseSets = WorkoutSetLogging.sortedByCompletedAt(
                sessionSets.filter { $0.exerciseOrderIndex == descriptor.orderIndex }
            )
            let lastCurrentSet = exerciseSets.last
            let historySet: WorkoutSet?
            if lastCurrentSet == nil {
                historySet = try historicalLastSet(
                    currentSessionID: session.id,
                    exercise: descriptor.exercise,
                    exerciseName: descriptor.name,
                    in: context
                )
            } else {
                historySet = nil
            }

            return WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: descriptor.orderIndex,
                name: descriptor.name,
                completedSetCount: exerciseSets.count,
                weightUnit: descriptor.weightUnit.rawValue,
                isUnilateral: descriptor.isUnilateral,
                defaultRestSeconds: descriptor.defaultRestSeconds,
                leftCompletedSetCount: exerciseSets.filter { $0.side == .left }.count,
                rightCompletedSetCount: exerciseSets.filter { $0.side == .right }.count,
                lastSetReference: reference(
                    currentSet: lastCurrentSet,
                    historySet: historySet,
                    weightUnit: descriptor.weightUnit
                )
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

    private static func setsForSession(sessionID: UUID, in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(
            FetchDescriptor<WorkoutSet>(
                predicate: #Predicate<WorkoutSet> { set in
                    set.session?.id == sessionID
                },
                sortBy: [
                    SortDescriptor(\WorkoutSet.completedAt),
                    SortDescriptor(\WorkoutSet.setIndex),
                ]
            )
        )
    }

    private static func historicalLastSet(
        currentSessionID: UUID,
        exercise: Exercise?,
        exerciseName: String,
        in context: ModelContext
    ) throws -> WorkoutSet? {
        if let exercise {
            let exerciseID = exercise.persistentModelID
            if let set = try firstHistoricalSet(
                currentSessionID: currentSessionID,
                predicate: #Predicate<WorkoutSet> { set in
                    set.exercise?.persistentModelID == exerciseID
                },
                in: context
            ) {
                return set
            }
        }

        return try firstHistoricalSet(
            currentSessionID: currentSessionID,
            predicate: #Predicate<WorkoutSet> { set in
                set.exerciseNameSnapshot == exerciseName ||
                    (set.exerciseNameSnapshot == "" && set.exercise?.name == exerciseName)
            },
            in: context
        )
    }

    private static func firstHistoricalSet(
        currentSessionID: UUID,
        predicate: Predicate<WorkoutSet>,
        in context: ModelContext
    ) throws -> WorkoutSet? {
        var offset = 0
        var pageCount = 0

        while true {
            guard pageCount < historyReferenceMaxPages else {
                return nil
            }

            var descriptor = FetchDescriptor<WorkoutSet>(
                predicate: predicate,
                sortBy: [SortDescriptor(\WorkoutSet.completedAt, order: .reverse)]
            )
            descriptor.fetchLimit = historyReferencePageSize
            descriptor.fetchOffset = offset

            let page = try context.fetch(descriptor)

            if let set = page.first(where: { $0.session?.id != currentSessionID }) {
                return set
            }

            guard page.count == historyReferencePageSize else {
                return nil
            }

            offset += historyReferencePageSize
            pageCount += 1
        }
    }

    private static func reference(
        currentSet: WorkoutSet?,
        historySet: WorkoutSet?,
        weightUnit: WeightUnit
    ) -> WatchWorkoutSnapshot.LastSetReference? {
        if let currentSet {
            return WatchWorkoutSnapshot.LastSetReference(
                weight: weightUnit.displayValue(fromKilograms: currentSet.weight),
                reps: currentSet.reps,
                source: "currentSession"
            )
        }

        guard let historySet else {
            return nil
        }

        return WatchWorkoutSnapshot.LastSetReference(
            weight: weightUnit.displayValue(fromKilograms: historySet.weight),
            reps: historySet.reps,
            source: "history"
        )
    }
}
