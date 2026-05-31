import Foundation

struct WatchTrainingStateMessage: Equatable {
    static let schemaVersion = 1

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
        case unexpectedIsTraining
    }

    let kind: Kind
    let requestID: String?
    let sentAt: TimeInterval
    let isTraining: Bool?

    var propertyList: [String: Any] {
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

        return message
    }

    static func request(requestID: String, sentAt: TimeInterval) -> WatchTrainingStateMessage {
        WatchTrainingStateMessage(
            kind: .request,
            requestID: requestID,
            sentAt: sentAt,
            isTraining: nil
        )
    }

    static func response(requestID: String, sentAt: TimeInterval, isTraining: Bool) -> WatchTrainingStateMessage {
        WatchTrainingStateMessage(
            kind: .response,
            requestID: requestID,
            sentAt: sentAt,
            isTraining: isTraining
        )
    }

    static func update(requestID: String? = nil, sentAt: TimeInterval, isTraining: Bool) -> WatchTrainingStateMessage {
        WatchTrainingStateMessage(
            kind: .update,
            requestID: requestID,
            sentAt: sentAt,
            isTraining: isTraining
        )
    }

    init(propertyList: [String: Any]) throws {
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

        switch kind {
        case .request:
            guard let requestID, requestID.isEmpty == false else {
                throw ParseError.invalidRequestID
            }

            guard propertyList["isTraining"] == nil else {
                throw ParseError.unexpectedIsTraining
            }

            self.isTraining = nil
        case .response:
            guard let requestID, requestID.isEmpty == false else {
                throw ParseError.invalidRequestID
            }

            guard let isTraining = propertyList["isTraining"] as? Bool else {
                throw ParseError.invalidIsTraining
            }

            self.isTraining = isTraining
        case .update:
            guard let isTraining = propertyList["isTraining"] as? Bool else {
                throw ParseError.invalidIsTraining
            }

            self.isTraining = isTraining
        }

        self.kind = kind
        self.requestID = requestID
        self.sentAt = sentAt
    }

    private init(
        kind: Kind,
        requestID: String?,
        sentAt: TimeInterval,
        isTraining: Bool?
    ) {
        self.kind = kind
        self.requestID = requestID
        self.sentAt = sentAt
        self.isTraining = isTraining
    }
}
