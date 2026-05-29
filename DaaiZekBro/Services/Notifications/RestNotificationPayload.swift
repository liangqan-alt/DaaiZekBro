import Foundation

struct RestNotificationPayload: Equatable {
    static let sessionIDKey = "sessionId"
    static let exerciseOrderIndexKey = "exerciseOrderIndex"
    static let exerciseNameKey = "exerciseName"

    let sessionID: UUID
    let exerciseOrderIndex: Int?
    let exerciseName: String

    init(sessionID: UUID, exerciseName: String, exerciseOrderIndex: Int? = nil) {
        self.sessionID = sessionID
        self.exerciseOrderIndex = exerciseOrderIndex
        self.exerciseName = exerciseName
    }

    init?(userInfo: [AnyHashable: Any]) {
        let exerciseOrderIndex = Self.exerciseOrderIndex(from: userInfo)
        guard exerciseOrderIndex != nil || userInfo[Self.exerciseOrderIndexKey] == nil else {
            return nil
        }

        guard
            let sessionIDString = userInfo[Self.sessionIDKey] as? String,
            let sessionID = UUID(uuidString: sessionIDString),
            let exerciseName = userInfo[Self.exerciseNameKey] as? String,
            exerciseName.isEmpty == false
        else {
            return nil
        }

        self.sessionID = sessionID
        self.exerciseOrderIndex = exerciseOrderIndex
        self.exerciseName = exerciseName
    }

    var userInfo: [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            Self.sessionIDKey: sessionID.uuidString,
            Self.exerciseNameKey: exerciseName,
        ]

        if let exerciseOrderIndex {
            userInfo[Self.exerciseOrderIndexKey] = exerciseOrderIndex
        }

        return userInfo
    }

    private static func exerciseOrderIndex(from userInfo: [AnyHashable: Any]) -> Int? {
        switch userInfo[Self.exerciseOrderIndexKey] {
        case let index as Int:
            return index
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}
