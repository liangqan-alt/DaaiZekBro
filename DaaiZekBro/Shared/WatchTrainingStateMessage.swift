import Foundation

struct WatchTrainingStateMessage: Equatable {
    nonisolated static let schemaVersion = 1

    enum Kind: String {
        case request = "trainingState.request"
        case response = "trainingState.response"
        case update = "trainingState.update"
    }

    enum ParseError: Error, Equatable {
        case invalidSchemaVersion
        case invalidKind
        case invalidRequestID
        case invalidSentAt
        case invalidIsTraining
        case invalidSnapshot
        case unexpectedIsTraining
    }

    let kind: Kind
    let requestID: String?
    let sentAt: TimeInterval
    let isTraining: Bool?
    let snapshot: WatchWorkoutSnapshot?

    nonisolated var propertyList: [String: Any] {
        var message: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "kind": kind.rawValue,
            "sentAt": sentAt,
        ]

        if let requestID {
            message["requestID"] = requestID
        }

        if let isTraining {
            message["isTraining"] = isTraining
        }

        if let snapshot {
            message["snapshot"] = snapshot.propertyList
        }

        return message
    }

    nonisolated static func request(requestID: String, sentAt: TimeInterval) -> WatchTrainingStateMessage {
        WatchTrainingStateMessage(
            kind: .request,
            requestID: requestID,
            sentAt: sentAt,
            isTraining: nil,
            snapshot: nil
        )
    }

    nonisolated static func response(
        requestID: String,
        sentAt: TimeInterval,
        isTraining: Bool,
        snapshot: WatchWorkoutSnapshot? = nil
    ) -> WatchTrainingStateMessage {
        WatchTrainingStateMessage(
            kind: .response,
            requestID: requestID,
            sentAt: sentAt,
            isTraining: isTraining,
            snapshot: snapshot
        )
    }

    nonisolated static func update(
        requestID: String? = nil,
        sentAt: TimeInterval,
        isTraining: Bool,
        snapshot: WatchWorkoutSnapshot? = nil
    ) -> WatchTrainingStateMessage {
        WatchTrainingStateMessage(
            kind: .update,
            requestID: requestID,
            sentAt: sentAt,
            isTraining: isTraining,
            snapshot: snapshot
        )
    }

    nonisolated init(propertyList: [String: Any]) throws {
        guard let schemaVersion = propertyList["schemaVersion"] as? Int,
              schemaVersion == Self.schemaVersion else {
            throw ParseError.invalidSchemaVersion
        }

        guard let kindValue = propertyList["kind"] as? String,
              let kind = Kind(rawValue: kindValue) else {
            throw ParseError.invalidKind
        }

        guard let sentAt = propertyList["sentAt"] as? TimeInterval else {
            throw ParseError.invalidSentAt
        }

        let requestID = propertyList["requestID"] as? String
        let snapshot: WatchWorkoutSnapshot?

        switch kind {
        case .request:
            guard let requestID, requestID.isEmpty == false else {
                throw ParseError.invalidRequestID
            }

            guard propertyList["isTraining"] == nil else {
                throw ParseError.unexpectedIsTraining
            }

            self.isTraining = nil
            snapshot = nil
        case .response:
            guard let requestID, requestID.isEmpty == false else {
                throw ParseError.invalidRequestID
            }

            guard let isTraining = propertyList["isTraining"] as? Bool else {
                throw ParseError.invalidIsTraining
            }

            self.isTraining = isTraining
            snapshot = try Self.parseSnapshot(from: propertyList)
        case .update:
            guard let isTraining = propertyList["isTraining"] as? Bool else {
                throw ParseError.invalidIsTraining
            }

            self.isTraining = isTraining
            snapshot = try Self.parseSnapshot(from: propertyList)
        }

        self.kind = kind
        self.requestID = requestID
        self.sentAt = sentAt
        self.snapshot = snapshot
    }

    private nonisolated init(
        kind: Kind,
        requestID: String?,
        sentAt: TimeInterval,
        isTraining: Bool?,
        snapshot: WatchWorkoutSnapshot?
    ) {
        self.kind = kind
        self.requestID = requestID
        self.sentAt = sentAt
        self.isTraining = isTraining
        self.snapshot = snapshot
    }

    private nonisolated static func parseSnapshot(from propertyList: [String: Any]) throws -> WatchWorkoutSnapshot? {
        guard let snapshotPropertyList = propertyList["snapshot"] else {
            return nil
        }

        guard let snapshotPropertyList = snapshotPropertyList as? [String: Any] else {
            throw ParseError.invalidSnapshot
        }

        do {
            return try WatchWorkoutSnapshot(propertyList: snapshotPropertyList)
        } catch {
            throw ParseError.invalidSnapshot
        }
    }
}
