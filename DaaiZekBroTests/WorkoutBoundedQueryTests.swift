import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct WorkoutBoundedQueryTests {
    @Test func setsForExerciseUsesSessionLocalNameFallbackOnly() throws {
        let context = try makeInMemoryContext()
        let benchPress = Exercise(name: "Bench Press")
        let squat = Exercise(name: "Squat")
        let targetSession = WorkoutSession(startedAt: Date(timeIntervalSince1970: 100))
        let otherSession = WorkoutSession(startedAt: Date(timeIntervalSince1970: 200))

        context.insert(benchPress)
        context.insert(squat)
        context.insert(targetSession)
        context.insert(otherSession)

        let targetSnapshotSet = workoutSet(
            session: targetSession,
            exercise: benchPress,
            exerciseNameSnapshot: "Bench Press",
            setIndex: 2,
            weight: 42.5,
            completedAt: 200
        )
        let targetFallbackSet = workoutSet(
            session: targetSession,
            exercise: benchPress,
            exerciseNameSnapshot: "",
            setIndex: 1,
            weight: 40,
            completedAt: 100
        )
        let sameExerciseOtherSessionSet = workoutSet(
            session: otherSession,
            exercise: benchPress,
            exerciseNameSnapshot: "",
            setIndex: 1,
            weight: 99,
            completedAt: 50
        )
        let differentExerciseSet = workoutSet(
            session: targetSession,
            exercise: squat,
            exerciseNameSnapshot: "",
            setIndex: 3,
            weight: 120,
            completedAt: 300
        )

        context.insert(targetSnapshotSet)
        context.insert(targetFallbackSet)
        context.insert(sameExerciseOtherSessionSet)
        context.insert(differentExerciseSet)
        try context.save()

        let sets = try WorkoutSetLogging.setsForExercise(
            sessionID: targetSession.id,
            exerciseName: "Bench Press",
            in: context
        )

        #expect(sets.map(\.persistentModelID) == [
            targetFallbackSet.persistentModelID,
            targetSnapshotSet.persistentModelID,
        ])
    }

    @Test func currentOpenSessionReturnsMostRecentStartedOpenSession() throws {
        let context = try makeInMemoryContext()
        let olderOpenSession = WorkoutSession(startedAt: Date(timeIntervalSince1970: 100))
        let newerOpenSession = WorkoutSession(startedAt: Date(timeIntervalSince1970: 300))
        let endedNewestSession = WorkoutSession(
            startedAt: Date(timeIntervalSince1970: 400),
            endedAt: Date(timeIntervalSince1970: 500)
        )

        context.insert(olderOpenSession)
        context.insert(newerOpenSession)
        context.insert(endedNewestSession)
        try context.save()

        let currentSession = try WorkoutSessionLifecycle.currentOpenSession(in: context)

        #expect(currentSession?.persistentModelID == newerOpenSession.persistentModelID)
    }

    @Test func lastSetMatchesLegacyIdentityAndNameSemantics() throws {
        let context = try makeInMemoryContext()
        let primaryBench = Exercise(name: "Bench Press")
        let sameNameBench = Exercise(name: "Bench Press")
        let squat = Exercise(name: "Squat")
        let session = WorkoutSession(startedAt: Date(timeIntervalSince1970: 100))

        context.insert(primaryBench)
        context.insert(sameNameBench)
        context.insert(squat)
        context.insert(session)

        let primaryOlder = workoutSet(
            session: session,
            exercise: primaryBench,
            exerciseNameSnapshot: "Bench Press",
            weight: 40,
            completedAt: 100
        )
        let sameNameNewest = workoutSet(
            session: session,
            exercise: sameNameBench,
            exerciseNameSnapshot: "Bench Press",
            weight: 99,
            completedAt: 500
        )
        let snapshotOnlyNewer = workoutSet(
            session: session,
            exercise: nil,
            exerciseNameSnapshot: "Bench Press",
            weight: 100,
            completedAt: 600
        )
        let primaryRightFallback = workoutSet(
            session: session,
            exercise: primaryBench,
            exerciseNameSnapshot: "",
            weight: 55,
            side: .right,
            completedAt: 700
        )
        let snapshotWinsOverExerciseName = workoutSet(
            session: session,
            exercise: primaryBench,
            exerciseNameSnapshot: "Old Bench Press",
            weight: 77,
            completedAt: 900
        )
        let differentExerciseFallback = workoutSet(
            session: session,
            exercise: squat,
            exerciseNameSnapshot: "",
            weight: 120,
            completedAt: 1_000
        )
        let newerWrongSideSets = (0..<64).map { index in
            workoutSet(
                session: session,
                exercise: primaryBench,
                exerciseNameSnapshot: "",
                weight: Double(index),
                side: .right,
                completedAt: 2_000 + TimeInterval(index)
            )
        }

        for set in [
            primaryOlder,
            sameNameNewest,
            snapshotOnlyNewer,
            primaryRightFallback,
            snapshotWinsOverExerciseName,
            differentExerciseFallback,
        ] + newerWrongSideSets {
            context.insert(set)
        }
        try context.save()

        try expectLastSet(
            WorkoutSetLogging.lastSet(exercise: primaryBench, side: nil, in: context),
            matches: legacyLastSet(exercise: primaryBench, side: nil, in: context)
        )
        #expect(try WorkoutSetLogging.lastSet(
            exercise: primaryBench,
            side: nil,
            in: context
        )?.persistentModelID == snapshotWinsOverExerciseName.persistentModelID)

        try expectLastSet(
            WorkoutSetLogging.lastSet(exerciseName: "Bench Press", side: nil, in: context),
            matches: legacyLastSet(exerciseName: "Bench Press", side: nil, in: context)
        )
        #expect(try WorkoutSetLogging.lastSet(
            exerciseName: "Bench Press",
            side: nil,
            in: context
        )?.persistentModelID == snapshotOnlyNewer.persistentModelID)

        try expectLastSet(
            WorkoutSetLogging.lastSet(exercise: primaryBench, side: .right, in: context),
            matches: legacyLastSet(exercise: primaryBench, side: .right, in: context)
        )
        try expectLastSet(
            WorkoutSetLogging.lastSet(exerciseName: "Bench Press", side: .right, in: context),
            matches: legacyLastSet(exerciseName: "Bench Press", side: .right, in: context)
        )
        #expect(try WorkoutSetLogging.lastSet(
            exerciseName: "Bench Press",
            side: .right,
            in: context
        )?.persistentModelID == newerWrongSideSets.last?.persistentModelID)
    }

    private func expectLastSet(_ actual: WorkoutSet?, matches expected: WorkoutSet?) throws {
        #expect(actual?.persistentModelID == expected?.persistentModelID)
    }

    private func legacyLastSet(
        exercise: Exercise,
        side: Side?,
        in context: ModelContext
    ) throws -> WorkoutSet? {
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())

        return allSets
            .filter { set in
                guard let setExercise = set.exercise else {
                    return false
                }

                return (
                    setExercise === exercise ||
                    setExercise.persistentModelID == exercise.persistentModelID
                ) && set.side == side
            }
            .sorted { lhs, rhs in
                lhs.completedAt > rhs.completedAt
            }
            .first
    }

    private func legacyLastSet(
        exerciseName: String,
        side: Side?,
        in context: ModelContext
    ) throws -> WorkoutSet? {
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())

        return allSets
            .filter { set in
                legacyExerciseName(for: set) == exerciseName && set.side == side
            }
            .sorted { lhs, rhs in
                lhs.completedAt > rhs.completedAt
            }
            .first
    }

    private func legacyExerciseName(for set: WorkoutSet) -> String? {
        if set.exerciseNameSnapshot.isEmpty == false {
            return set.exerciseNameSnapshot
        }

        return set.exercise?.name
    }

    private func workoutSet(
        session: WorkoutSession,
        exercise: Exercise?,
        exerciseNameSnapshot: String,
        setIndex: Int = 1,
        weight: Double,
        side: Side? = nil,
        completedAt: TimeInterval
    ) -> WorkoutSet {
        WorkoutSet(
            session: session,
            exercise: exercise,
            exerciseNameSnapshot: exerciseNameSnapshot,
            setIndex: setIndex,
            weight: weight,
            reps: 8,
            side: side,
            completedAt: Date(timeIntervalSince1970: completedAt)
        )
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

        return ModelContext(container)
    }
}
