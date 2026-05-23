import Foundation

struct RestNotificationPayload: Equatable {
    static let sessionIDKey = "sessionId"
    static let exerciseNameKey = "exerciseName"

    let sessionID: UUID
    let exerciseName: String

    init(sessionID: UUID, exerciseName: String) {
        self.sessionID = sessionID
        self.exerciseName = exerciseName
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let sessionIDString = userInfo[Self.sessionIDKey] as? String,
            let sessionID = UUID(uuidString: sessionIDString),
            let exerciseName = userInfo[Self.exerciseNameKey] as? String,
            exerciseName.isEmpty == false
        else {
            return nil
        }

        self.sessionID = sessionID
        self.exerciseName = exerciseName
    }

    var userInfo: [AnyHashable: Any] {
        [
            Self.sessionIDKey: sessionID.uuidString,
            Self.exerciseNameKey: exerciseName,
        ]
    }
}
