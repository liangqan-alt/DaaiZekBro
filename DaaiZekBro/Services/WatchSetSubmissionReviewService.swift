import Foundation
import SwiftData

struct WatchSetSubmissionReviewCandidate: Equatable, Identifiable {
    let sessionID: UUID
    let sessionName: String
    let sessionStartedAt: Date
    let exerciseOrderIndex: Int
    let exerciseName: String

    var id: String {
        "\(sessionID.uuidString)-\(exerciseOrderIndex)"
    }
}

enum WatchSetSubmissionReviewError: Error, LocalizedError, Equatable {
    case recordAlreadyResolved
    case targetSessionNotFound
    case targetExerciseNotFound

    var errorDescription: String? {
        switch self {
        case .recordAlreadyResolved:
            "记录已处理"
        case .targetSessionNotFound:
            "目标训练不存在"
        case .targetExerciseNotFound:
            "目标训练不含可匹配动作"
        }
    }
}

@MainActor
enum WatchSetSubmissionReviewService {
    static func unresolvedRecords(in context: ModelContext) throws -> [WatchSetSubmissionRecord] {
        let status = WatchSetSubmissionRecordStatus.needsUserAction.rawValue
        let descriptor = FetchDescriptor<WatchSetSubmissionRecord>(
            predicate: #Predicate<WatchSetSubmissionRecord> { record in
                record.statusRawValue == status
            },
            sortBy: [
                SortDescriptor(\WatchSetSubmissionRecord.completedAt, order: .reverse),
                SortDescriptor(\WatchSetSubmissionRecord.createdAt, order: .reverse),
            ]
        )

        return try context.fetch(descriptor)
    }

    static func candidates(
        for record: WatchSetSubmissionRecord,
        in context: ModelContext
    ) throws -> [WatchSetSubmissionReviewCandidate] {
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
            )
        )
        var candidates: [WatchSetSubmissionReviewCandidate] = []

        for session in sessions {
            let descriptors = try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context)
            let matchingDescriptors = descriptors.filter { descriptor in
                descriptor.name == record.exerciseName
                    && sideIsCompatible(record.side, with: descriptor)
            }

            for descriptor in matchingDescriptors {
                candidates.append(
                    WatchSetSubmissionReviewCandidate(
                        sessionID: session.id,
                        sessionName: session.templateNameSnapshot,
                        sessionStartedAt: session.startedAt,
                        exerciseOrderIndex: descriptor.orderIndex,
                        exerciseName: descriptor.name
                    )
                )
            }
        }

        return candidates
    }

    @discardableResult
    static func relocate(
        record: WatchSetSubmissionRecord,
        toSessionID sessionID: UUID,
        exerciseOrderIndex: Int,
        in context: ModelContext
    ) throws -> WorkoutSet {
        guard record.status == .needsUserAction else {
            throw WatchSetSubmissionReviewError.recordAlreadyResolved
        }

        guard let session = try session(with: sessionID, in: context) else {
            throw WatchSetSubmissionReviewError.targetSessionNotFound
        }

        guard let descriptor = try WorkoutSessionLifecycle.exerciseDescriptor(
            orderIndex: exerciseOrderIndex,
            for: session,
            in: context
        ),
        descriptor.name == record.exerciseName,
        sideIsCompatible(record.side, with: descriptor) else {
            throw WatchSetSubmissionReviewError.targetExerciseNotFound
        }

        let previousCompletedSetCount = try WorkoutSetLogging.setsForExercise(
            sessionID: sessionID,
            exerciseOrderIndex: exerciseOrderIndex,
            in: context
        ).count
        let set = try WorkoutSetLogging.recordWatchSet(
            sessionID: sessionID,
            exerciseOrderIndex: exerciseOrderIndex,
            exerciseName: descriptor.name,
            weight: record.weightUnit.kilograms(fromDisplayValue: record.weight),
            reps: record.reps,
            rpe: record.rpe,
            side: record.side,
            completedAt: record.completedAt,
            saveImmediately: false,
            in: context
        )

        record.status = .saved
        record.reason = nil
        record.message = ""
        record.savedSetIndex = set.setIndex
        record.completedSetCount = previousCompletedSetCount + 1
        record.resolvedSessionID = sessionID.uuidString
        record.resolvedExerciseOrderIndex = exerciseOrderIndex
        record.updatedAt = Date()

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return set
    }

    static func discard(record: WatchSetSubmissionRecord, in context: ModelContext) throws {
        guard record.status == .needsUserAction else {
            throw WatchSetSubmissionReviewError.recordAlreadyResolved
        }

        record.status = .discarded
        record.message = "已丢弃"
        record.updatedAt = Date()
        try context.save()
    }

    private static func sideIsCompatible(
        _ side: Side?,
        with descriptor: WorkoutSessionExerciseDescriptor
    ) -> Bool {
        if side == nil {
            return descriptor.isUnilateral == false
        }

        return descriptor.isUnilateral
    }

    private static func session(with id: UUID, in context: ModelContext) throws -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { session in
                session.id == id
            }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }
}
