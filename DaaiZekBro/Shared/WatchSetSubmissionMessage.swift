import Foundation

enum WatchSetSubmissionManualReviewReason: String {
    case syncTimeout
    case sessionNotFound
    case exerciseNotFound
}

struct WatchSetSubmissionMessage: Equatable {
    nonisolated static let schemaVersion = 1
    nonisolated static let kind = "setSubmission.submit"

    enum ParseError: Error, Equatable {
        case invalidSchemaVersion
        case invalidKind
        case invalidClientSubmissionID
        case invalidSentAt
        case invalidSessionID
        case invalidSessionName
        case invalidSessionStartedAt
        case invalidExerciseOrderIndex
        case invalidExerciseName
        case invalidWeight
        case invalidWeightUnit
        case invalidReps
        case invalidRPE
        case invalidSide
        case invalidCompletedAt
        case invalidManualReviewReason
    }

    let clientSubmissionID: String
    let sentAt: TimeInterval
    let sessionID: String
    let sessionName: String?
    let sessionStartedAt: TimeInterval?
    let exerciseOrderIndex: Int
    let exerciseName: String
    let weight: Double
    let weightUnit: String
    let reps: Int
    let rpe: Int?
    let side: String?
    let completedAt: TimeInterval
    let manualReviewReason: WatchSetSubmissionManualReviewReason?

    nonisolated var propertyList: [String: Any] {
        var propertyList: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "kind": Self.kind,
            "clientSubmissionID": clientSubmissionID,
            "sentAt": sentAt,
            "sessionID": sessionID,
            "exerciseOrderIndex": exerciseOrderIndex,
            "exerciseName": exerciseName,
            "weight": weight,
            "weightUnit": weightUnit,
            "reps": reps,
            "completedAt": completedAt,
        ]

        if let rpe {
            propertyList["rpe"] = rpe
        }

        if let side {
            propertyList["side"] = side
        }

        if let sessionName {
            propertyList["sessionName"] = sessionName
        }

        if let sessionStartedAt {
            propertyList["sessionStartedAt"] = sessionStartedAt
        }

        if let manualReviewReason {
            propertyList["manualReviewReason"] = manualReviewReason.rawValue
        }

        return propertyList
    }

    nonisolated init(
        clientSubmissionID: String,
        sentAt: TimeInterval,
        sessionID: String,
        sessionName: String? = nil,
        sessionStartedAt: TimeInterval? = nil,
        exerciseOrderIndex: Int,
        exerciseName: String,
        weight: Double,
        weightUnit: String,
        reps: Int,
        rpe: Int?,
        side: String?,
        completedAt: TimeInterval,
        manualReviewReason: WatchSetSubmissionManualReviewReason? = nil
    ) {
        self.clientSubmissionID = clientSubmissionID
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.sessionStartedAt = sessionStartedAt
        self.exerciseOrderIndex = exerciseOrderIndex
        self.exerciseName = exerciseName
        self.weight = weight
        self.weightUnit = weightUnit
        self.reps = reps
        self.rpe = rpe
        self.side = side
        self.completedAt = completedAt
        self.manualReviewReason = manualReviewReason
    }

    nonisolated init(propertyList: [String: Any]) throws {
        guard let schemaVersion = propertyList["schemaVersion"] as? Int,
              schemaVersion == Self.schemaVersion else {
            throw ParseError.invalidSchemaVersion
        }

        guard propertyList["kind"] as? String == Self.kind else {
            throw ParseError.invalidKind
        }

        guard let clientSubmissionID = propertyList["clientSubmissionID"] as? String,
              clientSubmissionID.isEmpty == false else {
            throw ParseError.invalidClientSubmissionID
        }

        guard let sentAt = propertyList["sentAt"] as? TimeInterval,
              sentAt.isFinite else {
            throw ParseError.invalidSentAt
        }

        guard let sessionID = propertyList["sessionID"] as? String,
              UUID(uuidString: sessionID) != nil else {
            throw ParseError.invalidSessionID
        }

        let sessionName: String?
        if let value = propertyList["sessionName"] {
            guard let parsed = value as? String,
                  parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw ParseError.invalidSessionName
            }
            sessionName = parsed
        } else {
            sessionName = nil
        }

        let sessionStartedAt: TimeInterval?
        if let value = propertyList["sessionStartedAt"] {
            guard let parsed = value as? TimeInterval,
                  parsed.isFinite else {
                throw ParseError.invalidSessionStartedAt
            }
            sessionStartedAt = parsed
        } else {
            sessionStartedAt = nil
        }

        guard let exerciseOrderIndex = propertyList["exerciseOrderIndex"] as? Int,
              exerciseOrderIndex >= 0 else {
            throw ParseError.invalidExerciseOrderIndex
        }

        guard let exerciseName = propertyList["exerciseName"] as? String,
              exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ParseError.invalidExerciseName
        }

        guard let weight = propertyList["weight"] as? Double,
              weight.isFinite,
              weight >= 0 else {
            throw ParseError.invalidWeight
        }

        guard let weightUnit = propertyList["weightUnit"] as? String,
              weightUnit == "kg" || weightUnit == "lb" else {
            throw ParseError.invalidWeightUnit
        }

        guard let reps = propertyList["reps"] as? Int,
              reps >= 1 else {
            throw ParseError.invalidReps
        }

        let rpe: Int?
        if let value = propertyList["rpe"] {
            guard let parsed = value as? Int,
                  6...10 ~= parsed else {
                throw ParseError.invalidRPE
            }
            rpe = parsed
        } else {
            rpe = nil
        }

        let side: String?
        if let value = propertyList["side"] {
            guard let parsed = value as? String,
                  parsed == "left" || parsed == "right" else {
                throw ParseError.invalidSide
            }
            side = parsed
        } else {
            side = nil
        }

        guard let completedAt = propertyList["completedAt"] as? TimeInterval,
              completedAt.isFinite else {
            throw ParseError.invalidCompletedAt
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

        self.clientSubmissionID = clientSubmissionID
        self.sentAt = sentAt
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.sessionStartedAt = sessionStartedAt
        self.exerciseOrderIndex = exerciseOrderIndex
        self.exerciseName = exerciseName
        self.weight = weight
        self.weightUnit = weightUnit
        self.reps = reps
        self.rpe = rpe
        self.side = side
        self.completedAt = completedAt
        self.manualReviewReason = manualReviewReason
    }
}

struct WatchSetSubmissionAck: Equatable {
    nonisolated static let schemaVersion = 1
    nonisolated static let kind = "setSubmission.ack"

    enum Status: String {
        case saved
        case needsUserAction
        case discarded
        case rejected
    }

    enum ErrorCode: String {
        case invalidPayload
        case modelContextUnavailable
        case sessionNotFound
        case sessionAlreadyEnded
        case exerciseNotFound
        case invalidWeight
        case invalidReps
        case invalidRPE
        case missingSide
        case sideNotAllowed
        case invalidWeightUnit
        case saveFailed
    }

    enum ParseError: Error, Equatable {
        case invalidSchemaVersion
        case invalidKind
        case invalidClientSubmissionID
        case invalidStatus
        case invalidSavedSetIndex
        case invalidCompletedSetCount
        case invalidManualReviewReason
        case invalidErrorCode
        case invalidMessage
    }

    let clientSubmissionID: String
    let status: Status
    let savedSetIndex: Int?
    let completedSetCount: Int?
    let manualReviewReason: WatchSetSubmissionManualReviewReason?
    let errorCode: ErrorCode?
    let message: String?

    nonisolated var propertyList: [String: Any] {
        var propertyList: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "kind": Self.kind,
            "clientSubmissionID": clientSubmissionID,
            "status": status.rawValue,
        ]

        if let savedSetIndex {
            propertyList["savedSetIndex"] = savedSetIndex
        }

        if let completedSetCount {
            propertyList["completedSetCount"] = completedSetCount
        }

        if let manualReviewReason {
            propertyList["manualReviewReason"] = manualReviewReason.rawValue
        }

        if let errorCode {
            propertyList["errorCode"] = errorCode.rawValue
        }

        if let message {
            propertyList["message"] = message
        }

        return propertyList
    }

    nonisolated static func saved(
        clientSubmissionID: String,
        savedSetIndex: Int,
        completedSetCount: Int
    ) -> WatchSetSubmissionAck {
        WatchSetSubmissionAck(
            clientSubmissionID: clientSubmissionID,
            status: .saved,
            savedSetIndex: savedSetIndex,
            completedSetCount: completedSetCount,
            manualReviewReason: nil,
            errorCode: nil,
            message: nil
        )
    }

    nonisolated static func rejected(
        clientSubmissionID: String,
        errorCode: ErrorCode,
        message: String
    ) -> WatchSetSubmissionAck {
        WatchSetSubmissionAck(
            clientSubmissionID: clientSubmissionID,
            status: .rejected,
            savedSetIndex: nil,
            completedSetCount: nil,
            manualReviewReason: nil,
            errorCode: errorCode,
            message: message
        )
    }

    nonisolated static func needsUserAction(
        clientSubmissionID: String,
        reason: WatchSetSubmissionManualReviewReason,
        message: String
    ) -> WatchSetSubmissionAck {
        WatchSetSubmissionAck(
            clientSubmissionID: clientSubmissionID,
            status: .needsUserAction,
            savedSetIndex: nil,
            completedSetCount: nil,
            manualReviewReason: reason,
            errorCode: nil,
            message: message
        )
    }

    nonisolated static func discarded(
        clientSubmissionID: String,
        message: String = "已丢弃"
    ) -> WatchSetSubmissionAck {
        WatchSetSubmissionAck(
            clientSubmissionID: clientSubmissionID,
            status: .discarded,
            savedSetIndex: nil,
            completedSetCount: nil,
            manualReviewReason: nil,
            errorCode: nil,
            message: message
        )
    }

    nonisolated init(propertyList: [String: Any]) throws {
        guard let schemaVersion = propertyList["schemaVersion"] as? Int,
              schemaVersion == Self.schemaVersion else {
            throw ParseError.invalidSchemaVersion
        }

        guard propertyList["kind"] as? String == Self.kind else {
            throw ParseError.invalidKind
        }

        guard let clientSubmissionID = propertyList["clientSubmissionID"] as? String,
              clientSubmissionID.isEmpty == false else {
            throw ParseError.invalidClientSubmissionID
        }

        guard let statusValue = propertyList["status"] as? String,
              let status = Status(rawValue: statusValue) else {
            throw ParseError.invalidStatus
        }

        switch status {
        case .saved:
            guard let savedSetIndex = propertyList["savedSetIndex"] as? Int,
                  savedSetIndex >= 1 else {
                throw ParseError.invalidSavedSetIndex
            }

            guard let completedSetCount = propertyList["completedSetCount"] as? Int,
                  completedSetCount >= 1 else {
                throw ParseError.invalidCompletedSetCount
            }

            self.clientSubmissionID = clientSubmissionID
            self.status = status
            self.savedSetIndex = savedSetIndex
            self.completedSetCount = completedSetCount
            self.manualReviewReason = nil
            self.errorCode = nil
            self.message = nil
        case .needsUserAction:
            guard let reasonValue = propertyList["manualReviewReason"] as? String,
                  let manualReviewReason = WatchSetSubmissionManualReviewReason(rawValue: reasonValue) else {
                throw ParseError.invalidManualReviewReason
            }

            guard let message = propertyList["message"] as? String,
                  message.isEmpty == false else {
                throw ParseError.invalidMessage
            }

            self.clientSubmissionID = clientSubmissionID
            self.status = status
            self.savedSetIndex = nil
            self.completedSetCount = nil
            self.manualReviewReason = manualReviewReason
            self.errorCode = nil
            self.message = message
        case .discarded:
            guard let message = propertyList["message"] as? String,
                  message.isEmpty == false else {
                throw ParseError.invalidMessage
            }

            self.clientSubmissionID = clientSubmissionID
            self.status = status
            self.savedSetIndex = nil
            self.completedSetCount = nil
            self.manualReviewReason = nil
            self.errorCode = nil
            self.message = message
        case .rejected:
            guard let errorCodeValue = propertyList["errorCode"] as? String,
                  let errorCode = ErrorCode(rawValue: errorCodeValue) else {
                throw ParseError.invalidErrorCode
            }

            guard let message = propertyList["message"] as? String,
                  message.isEmpty == false else {
                throw ParseError.invalidMessage
            }

            self.clientSubmissionID = clientSubmissionID
            self.status = status
            self.savedSetIndex = nil
            self.completedSetCount = nil
            self.manualReviewReason = nil
            self.errorCode = errorCode
            self.message = message
        }
    }

    private nonisolated init(
        clientSubmissionID: String,
        status: Status,
        savedSetIndex: Int?,
        completedSetCount: Int?,
        manualReviewReason: WatchSetSubmissionManualReviewReason?,
        errorCode: ErrorCode?,
        message: String?
    ) {
        self.clientSubmissionID = clientSubmissionID
        self.status = status
        self.savedSetIndex = savedSetIndex
        self.completedSetCount = completedSetCount
        self.manualReviewReason = manualReviewReason
        self.errorCode = errorCode
        self.message = message
    }
}
