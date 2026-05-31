import Foundation
import SwiftData

@MainActor
enum PhoneWatchSetSubmissionHandler {
    static func handle(_ submission: WatchSetSubmissionMessage, in context: ModelContext) -> WatchSetSubmissionAck {
        if let existingRecord = try? record(clientSubmissionID: submission.clientSubmissionID, in: context) {
            return ack(for: existingRecord)
        }

        guard let sessionID = UUID(uuidString: submission.sessionID) else {
            return createRejectedRecord(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: .invalidPayload,
                message: "训练标识无效"
            )
        }

        guard let unit = WeightUnit(rawValue: submission.weightUnit) else {
            return createRejectedRecord(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: .invalidWeightUnit,
                message: "重量单位无效"
            )
        }

        let side = submission.side.flatMap(Side.init(rawValue:))
        let weightKilograms = unit.kilograms(fromDisplayValue: submission.weight)

        if submission.manualReviewReason == .syncTimeout {
            return createNeedsUserActionRecord(
                for: submission,
                unit: unit,
                side: side,
                reason: .syncTimeout,
                message: "同步超时，需在 iPhone 上处理",
                in: context
            )
        }

        do {
            let previousCompletedSetCount = try WorkoutSetLogging.setsForExercise(
                sessionID: sessionID,
                exerciseOrderIndex: submission.exerciseOrderIndex,
                in: context
            ).count
            let set = try WorkoutSetLogging.recordWatchSet(
                sessionID: sessionID,
                exerciseOrderIndex: submission.exerciseOrderIndex,
                exerciseName: submission.exerciseName,
                weight: weightKilograms,
                reps: submission.reps,
                rpe: submission.rpe,
                side: side,
                completedAt: Date(timeIntervalSince1970: submission.completedAt),
                saveImmediately: false,
                in: context
            )
            let completedSetCount = previousCompletedSetCount + 1

            let ack = WatchSetSubmissionAck.saved(
                clientSubmissionID: submission.clientSubmissionID,
                savedSetIndex: set.setIndex,
                completedSetCount: completedSetCount
            )
            try insertRecord(
                for: submission,
                unit: unit,
                side: side,
                status: .saved,
                reason: nil,
                message: "",
                savedSetIndex: set.setIndex,
                completedSetCount: completedSetCount,
                resolvedSessionID: sessionID,
                resolvedExerciseOrderIndex: submission.exerciseOrderIndex,
                in: context
            )

            return ack
        } catch let error as WorkoutSetLoggingError {
            context.rollback()

            switch error {
            case .sessionNotFound:
                return createNeedsUserActionRecord(
                    for: submission,
                    unit: unit,
                    side: side,
                    reason: .sessionNotFound,
                    message: "原训练不存在，需在 iPhone 上归位或丢弃",
                    in: context
                )
            case .exerciseNotFound:
                return createNeedsUserActionRecord(
                    for: submission,
                    unit: unit,
                    side: side,
                    reason: .exerciseNotFound,
                    message: "原动作不存在，需在 iPhone 上归位或丢弃",
                    in: context
                )
            default:
                break
            }

            return createRejectedRecord(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: errorCode(for: error),
                message: error.localizedDescription
            )
        } catch {
            context.rollback()

            return createRejectedRecord(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: .saveFailed,
                message: error.localizedDescription
            )
        }
    }

    static func rejectedInvalidPayload(from propertyList: [String: Any]) -> WatchSetSubmissionAck {
        .rejected(
            clientSubmissionID: clientSubmissionID(in: propertyList),
            errorCode: .invalidPayload,
            message: "提交数据无效"
        )
    }

    static func clientSubmissionID(in propertyList: [String: Any]) -> String {
        if let clientSubmissionID = propertyList["clientSubmissionID"] as? String,
           clientSubmissionID.isEmpty == false {
            return clientSubmissionID
        }

        return "invalid-submission"
    }

    private static func errorCode(for error: WorkoutSetLoggingError) -> WatchSetSubmissionAck.ErrorCode {
        switch error {
        case .sessionNotFound:
            .sessionNotFound
        case .sessionAlreadyEnded:
            .sessionAlreadyEnded
        case .exerciseNotFound:
            .exerciseNotFound
        case .invalidWeight:
            .invalidWeight
        case .invalidReps:
            .invalidReps
        case .invalidRPE:
            .invalidRPE
        case .missingSideForUnilateralExercise:
            .missingSide
        case .sideNotAllowedForBilateralExercise:
            .sideNotAllowed
        }
    }

    private static func ack(for record: WatchSetSubmissionRecord) -> WatchSetSubmissionAck {
        switch record.status {
        case .saved:
            return .saved(
                clientSubmissionID: record.clientSubmissionID,
                savedSetIndex: record.savedSetIndex ?? 1,
                completedSetCount: record.completedSetCount ?? 1
            )
        case .needsUserAction:
            return .needsUserAction(
                clientSubmissionID: record.clientSubmissionID,
                reason: manualReviewReason(for: record.reason),
                message: record.message.isEmpty ? "需在 iPhone 上处理" : record.message
            )
        case .discarded:
            return .discarded(
                clientSubmissionID: record.clientSubmissionID,
                message: record.message.isEmpty ? "已丢弃" : record.message
            )
        }
    }

    private static func createNeedsUserActionRecord(
        for submission: WatchSetSubmissionMessage,
        unit: WeightUnit,
        side: Side?,
        reason: WatchSetSubmissionRecordReason,
        message: String,
        in context: ModelContext
    ) -> WatchSetSubmissionAck {
        do {
            try insertRecord(
                for: submission,
                unit: unit,
                side: side,
                status: .needsUserAction,
                reason: reason,
                message: message,
                savedSetIndex: nil,
                completedSetCount: nil,
                resolvedSessionID: nil,
                resolvedExerciseOrderIndex: nil,
                in: context
            )
        } catch {
            context.rollback()
            return .rejected(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: .saveFailed,
                message: error.localizedDescription
            )
        }

        return .needsUserAction(
            clientSubmissionID: submission.clientSubmissionID,
            reason: manualReviewReason(for: reason),
            message: message
        )
    }

    private static func createRejectedRecord(
        clientSubmissionID: String,
        errorCode: WatchSetSubmissionAck.ErrorCode,
        message: String
    ) -> WatchSetSubmissionAck {
        return .rejected(
            clientSubmissionID: clientSubmissionID,
            errorCode: errorCode,
            message: message
        )
    }

    private static func insertRecord(
        for submission: WatchSetSubmissionMessage,
        unit: WeightUnit,
        side: Side?,
        status: WatchSetSubmissionRecordStatus,
        reason: WatchSetSubmissionRecordReason?,
        message: String,
        savedSetIndex: Int?,
        completedSetCount: Int?,
        resolvedSessionID: UUID?,
        resolvedExerciseOrderIndex: Int?,
        in context: ModelContext
    ) throws {
        let submittedAt = Date(timeIntervalSince1970: submission.sentAt)
        let completedAt = Date(timeIntervalSince1970: submission.completedAt)
        let sessionStartedAt = submission.sessionStartedAt.map(Date.init(timeIntervalSince1970:))
        let now = Date()
        let record = WatchSetSubmissionRecord(
            clientSubmissionID: submission.clientSubmissionID,
            originalSessionID: submission.sessionID,
            originalSessionName: submission.sessionName ?? "",
            originalSessionStartedAt: sessionStartedAt,
            exerciseOrderIndex: submission.exerciseOrderIndex,
            exerciseName: submission.exerciseName,
            weight: submission.weight,
            weightUnit: unit,
            reps: submission.reps,
            rpe: submission.rpe,
            side: side,
            completedAt: completedAt,
            submittedAt: submittedAt,
            status: status,
            reason: reason,
            message: message,
            savedSetIndex: savedSetIndex,
            completedSetCount: completedSetCount,
            resolvedSessionID: resolvedSessionID,
            resolvedExerciseOrderIndex: resolvedExerciseOrderIndex,
            createdAt: now,
            updatedAt: now
        )

        context.insert(record)
        try context.save()
    }

    private static func record(
        clientSubmissionID: String,
        in context: ModelContext
    ) throws -> WatchSetSubmissionRecord? {
        var descriptor = FetchDescriptor<WatchSetSubmissionRecord>(
            predicate: #Predicate<WatchSetSubmissionRecord> { record in
                record.clientSubmissionID == clientSubmissionID
            }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    private static func manualReviewReason(
        for reason: WatchSetSubmissionRecordReason?
    ) -> WatchSetSubmissionManualReviewReason {
        switch reason {
        case .sessionNotFound:
            .sessionNotFound
        case .exerciseNotFound:
            .exerciseNotFound
        case .syncTimeout, nil:
            .syncTimeout
        }
    }
}
