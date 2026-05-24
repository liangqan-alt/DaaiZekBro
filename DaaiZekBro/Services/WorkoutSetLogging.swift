import Foundation
import SwiftData

enum WorkoutSetLoggingError: Error, LocalizedError, Equatable {
    case sessionNotFound
    case sessionAlreadyEnded
    case exerciseNotFound
    case invalidWeight
    case invalidReps
    case invalidRPE(Int)
    case missingSideForUnilateralExercise
    case sideNotAllowedForBilateralExercise

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            "训练不存在"
        case .sessionAlreadyEnded:
            "训练已结束，不能继续记录"
        case .exerciseNotFound:
            "动作不存在"
        case .invalidWeight:
            "重量必须大于或等于 0"
        case .invalidReps:
            "次数必须大于或等于 1"
        case .invalidRPE(let rpe):
            "RPE 必须是 6 到 10 的整数，当前为 \(rpe)"
        case .missingSideForUnilateralExercise:
            "单侧动作必须选择左或右"
        case .sideNotAllowedForBilateralExercise:
            "双侧动作不能记录左或右"
        }
    }
}

struct WorkoutSetValues: Equatable {
    let weight: Double
    let reps: Int
}

struct WorkoutSideCounts: Equatable {
    let left: Int
    let right: Int
}

@MainActor
enum WorkoutSetLogging {
    static let allowedRPEValues = [6, 7, 8, 9, 10]

    static func recordSet(
        sessionID: UUID,
        exerciseName: String,
        weight: Double,
        reps: Int,
        rpe: Int?,
        side: Side?,
        completedAt: Date = Date(),
        in context: ModelContext
    ) throws -> WorkoutSet {
        let session = try session(with: sessionID, in: context)

        guard let exerciseDescriptor = try WorkoutSessionLifecycle.exerciseDescriptor(
            named: exerciseName,
            for: session,
            in: context
        ) else {
            throw WorkoutSetLoggingError.exerciseNotFound
        }

        guard session.endedAt == nil else {
            throw WorkoutSetLoggingError.sessionAlreadyEnded
        }

        try validate(weight: weight, reps: reps, rpe: rpe)
        let normalizedSide = try validatedSide(side, isUnilateral: exerciseDescriptor.isUnilateral)
        let nextSetIndex = try sets(
            sessionID: sessionID,
            exerciseName: exerciseDescriptor.name,
            side: normalizedSide,
            in: context
        ).count + 1

        let set = WorkoutSet(
            session: session,
            exercise: exerciseDescriptor.exercise,
            exerciseNameSnapshot: exerciseDescriptor.name,
            exerciseOrderIndex: exerciseDescriptor.orderIndex,
            setIndex: nextSetIndex,
            weight: weight,
            reps: reps,
            rpe: rpe,
            side: normalizedSide,
            completedAt: completedAt
        )

        context.insert(set)
        try context.save()

        return set
    }

    static func deleteAndRenumber(_ set: WorkoutSet, in context: ModelContext) throws {
        guard let sessionID = set.session?.id, let exerciseName = exerciseName(for: set) else {
            context.delete(set)
            try context.save()
            return
        }

        let remainingSets = try sets(
            sessionID: sessionID,
            exerciseName: exerciseName,
            side: set.side,
            in: context
        )
        .filter { $0 !== set }

        context.delete(set)

        for (index, remainingSet) in sortedByCompletedAt(remainingSets).enumerated() {
            remainingSet.setIndex = index + 1
        }

        try context.save()
    }

    static func setsForExercise(
        sessionID: UUID,
        exerciseName: String,
        in context: ModelContext
    ) throws -> [WorkoutSet] {
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())

        return sortedByCompletedAt(
            allSets.filter { set in
                set.session?.id == sessionID && self.exerciseName(for: set) == exerciseName
            }
        )
    }

    static func sets(
        sessionID: UUID,
        exerciseName: String,
        side: Side?,
        in context: ModelContext
    ) throws -> [WorkoutSet] {
        try setsForExercise(sessionID: sessionID, exerciseName: exerciseName, in: context)
            .filter { $0.side == side }
    }

    static func sideCounts(
        sessionID: UUID,
        exerciseName: String,
        in context: ModelContext
    ) throws -> WorkoutSideCounts {
        let exerciseSets = try setsForExercise(sessionID: sessionID, exerciseName: exerciseName, in: context)

        return WorkoutSideCounts(
            left: exerciseSets.filter { $0.side == .left }.count,
            right: exerciseSets.filter { $0.side == .right }.count
        )
    }

    static func inferredNextSide(
        sessionID: UUID,
        exerciseName: String,
        in context: ModelContext
    ) throws -> Side {
        let counts = try sideCounts(sessionID: sessionID, exerciseName: exerciseName, in: context)

        if counts.left > counts.right {
            return .right
        }

        return .left
    }

    static func lastValues(
        exercise: Exercise,
        side: Side?,
        in context: ModelContext
    ) throws -> WorkoutSetValues? {
        try lastSet(exercise: exercise, side: side, in: context).map {
            WorkoutSetValues(weight: $0.weight, reps: $0.reps)
        }
    }

    static func lastValues(
        exerciseName: String,
        side: Side?,
        in context: ModelContext
    ) throws -> WorkoutSetValues? {
        try lastSet(exerciseName: exerciseName, side: side, in: context).map {
            WorkoutSetValues(weight: $0.weight, reps: $0.reps)
        }
    }

    static func lastSet(
        exercise: Exercise,
        side: Side?,
        in context: ModelContext
    ) throws -> WorkoutSet? {
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())

        return allSets
            .filter { set in
                isSameExercise(set.exercise, as: exercise) && set.side == side
            }
            .sorted { lhs, rhs in
                lhs.completedAt > rhs.completedAt
            }
            .first
    }

    static func lastSet(
        exerciseName: String,
        side: Side?,
        in context: ModelContext
    ) throws -> WorkoutSet? {
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())

        return allSets
            .filter { set in
                self.exerciseName(for: set) == exerciseName && set.side == side
            }
            .sorted { lhs, rhs in
                lhs.completedAt > rhs.completedAt
            }
            .first
    }

    private static func isSameExercise(_ lhs: Exercise?, as rhs: Exercise) -> Bool {
        guard let lhs else {
            return false
        }

        return lhs === rhs || lhs.persistentModelID == rhs.persistentModelID
    }

    static func exerciseName(for set: WorkoutSet) -> String? {
        if set.exerciseNameSnapshot.isEmpty == false {
            return set.exerciseNameSnapshot
        }

        return set.exercise?.name
    }

    static func sortedByCompletedAt(_ sets: [WorkoutSet]) -> [WorkoutSet] {
        sets.sorted { lhs, rhs in
            if lhs.completedAt != rhs.completedAt {
                return lhs.completedAt < rhs.completedAt
            }

            return lhs.setIndex < rhs.setIndex
        }
    }

    private static func validate(weight: Double, reps: Int, rpe: Int?) throws {
        guard weight.isFinite, weight >= 0 else {
            throw WorkoutSetLoggingError.invalidWeight
        }

        guard reps >= 1 else {
            throw WorkoutSetLoggingError.invalidReps
        }

        if let rpe, allowedRPEValues.contains(rpe) == false {
            throw WorkoutSetLoggingError.invalidRPE(rpe)
        }
    }

    private static func validatedSide(_ side: Side?, isUnilateral: Bool) throws -> Side? {
        if isUnilateral {
            guard let side else {
                throw WorkoutSetLoggingError.missingSideForUnilateralExercise
            }

            return side
        }

        guard side == nil else {
            throw WorkoutSetLoggingError.sideNotAllowedForBilateralExercise
        }

        return nil
    }

    private static func session(with id: UUID, in context: ModelContext) throws -> WorkoutSession {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        guard let session = sessions.first(where: { $0.id == id }) else {
            throw WorkoutSetLoggingError.sessionNotFound
        }

        return session
    }

}
