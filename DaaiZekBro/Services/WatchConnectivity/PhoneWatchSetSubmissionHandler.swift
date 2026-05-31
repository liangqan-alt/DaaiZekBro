import Foundation
import SwiftData

@MainActor
enum PhoneWatchSetSubmissionHandler {
    static func handle(_ submission: WatchSetSubmissionMessage, in context: ModelContext) -> WatchSetSubmissionAck {
        guard let sessionID = UUID(uuidString: submission.sessionID) else {
            return .rejected(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: .invalidPayload,
                message: "训练标识无效"
            )
        }

        guard let unit = WeightUnit(rawValue: submission.weightUnit) else {
            return .rejected(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: .invalidWeightUnit,
                message: "重量单位无效"
            )
        }

        let side = submission.side.flatMap(Side.init(rawValue:))
        let weightKilograms = unit.kilograms(fromDisplayValue: submission.weight)

        do {
            let set = try WorkoutSetLogging.recordSet(
                sessionID: sessionID,
                exerciseOrderIndex: submission.exerciseOrderIndex,
                exerciseName: submission.exerciseName,
                weight: weightKilograms,
                reps: submission.reps,
                rpe: submission.rpe,
                side: side,
                completedAt: Date(timeIntervalSince1970: submission.completedAt),
                in: context
            )
            let completedSetCount = try WorkoutSetLogging.setsForExercise(
                sessionID: sessionID,
                exerciseOrderIndex: submission.exerciseOrderIndex,
                in: context
            ).count

            return .saved(
                clientSubmissionID: submission.clientSubmissionID,
                savedSetIndex: set.setIndex,
                completedSetCount: completedSetCount
            )
        } catch let error as WorkoutSetLoggingError {
            return .rejected(
                clientSubmissionID: submission.clientSubmissionID,
                errorCode: errorCode(for: error),
                message: error.localizedDescription
            )
        } catch {
            return .rejected(
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
}
