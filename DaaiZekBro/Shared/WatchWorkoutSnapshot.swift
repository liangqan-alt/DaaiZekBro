import Foundation

struct WatchWorkoutSnapshot: Equatable {
    enum ParseError: Error, Equatable {
        case invalidSessionID
        case invalidSessionName
        case invalidStartedAt
        case invalidExercises
        case invalidExercise
        case invalidExerciseName
        case invalidExerciseOrderIndex
        case invalidCompletedSetCount
        case invalidWeightUnit
        case invalidIsUnilateral
        case invalidDefaultRestSeconds
    }

    struct Exercise: Equatable {
        let exerciseOrderIndex: Int
        let name: String
        let completedSetCount: Int
        let weightUnit: String
        let isUnilateral: Bool
        let defaultRestSeconds: Int

        nonisolated var propertyList: [String: Any] {
            [
                "exerciseOrderIndex": exerciseOrderIndex,
                "name": name,
                "completedSetCount": completedSetCount,
                "weightUnit": weightUnit,
                "isUnilateral": isUnilateral,
                "defaultRestSeconds": defaultRestSeconds,
            ]
        }

        nonisolated init(
            exerciseOrderIndex: Int,
            name: String,
            completedSetCount: Int,
            weightUnit: String,
            isUnilateral: Bool,
            defaultRestSeconds: Int
        ) {
            self.exerciseOrderIndex = exerciseOrderIndex
            self.name = name
            self.completedSetCount = completedSetCount
            self.weightUnit = weightUnit
            self.isUnilateral = isUnilateral
            self.defaultRestSeconds = defaultRestSeconds
        }

        nonisolated init(propertyList: [String: Any]) throws {
            guard let name = propertyList["name"] as? String,
                  name.isEmpty == false else {
                throw ParseError.invalidExerciseName
            }

            guard let exerciseOrderIndex = propertyList["exerciseOrderIndex"] as? Int,
                  exerciseOrderIndex >= 0 else {
                throw ParseError.invalidExerciseOrderIndex
            }

            guard let completedSetCount = propertyList["completedSetCount"] as? Int,
                  completedSetCount >= 0 else {
                throw ParseError.invalidCompletedSetCount
            }

            guard let weightUnit = propertyList["weightUnit"] as? String,
                  weightUnit.isEmpty == false else {
                throw ParseError.invalidWeightUnit
            }

            guard let isUnilateral = propertyList["isUnilateral"] as? Bool else {
                throw ParseError.invalidIsUnilateral
            }

            guard let defaultRestSeconds = propertyList["defaultRestSeconds"] as? Int,
                  defaultRestSeconds >= 0 else {
                throw ParseError.invalidDefaultRestSeconds
            }

            self.exerciseOrderIndex = exerciseOrderIndex
            self.name = name
            self.completedSetCount = completedSetCount
            self.weightUnit = weightUnit
            self.isUnilateral = isUnilateral
            self.defaultRestSeconds = defaultRestSeconds
        }
    }

    let sessionID: String
    let sessionName: String
    let startedAt: TimeInterval
    let exercises: [Exercise]

    nonisolated var propertyList: [String: Any] {
        [
            "sessionID": sessionID,
            "sessionName": sessionName,
            "startedAt": startedAt,
            "exercises": exercises.map(\.propertyList),
        ]
    }

    nonisolated init(
        sessionID: String,
        sessionName: String,
        startedAt: TimeInterval,
        exercises: [Exercise]
    ) {
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.startedAt = startedAt
        self.exercises = exercises
    }

    nonisolated init(propertyList: [String: Any]) throws {
        guard let sessionID = propertyList["sessionID"] as? String,
              sessionID.isEmpty == false else {
            throw ParseError.invalidSessionID
        }

        guard let sessionName = propertyList["sessionName"] as? String,
              sessionName.isEmpty == false else {
            throw ParseError.invalidSessionName
        }

        guard let startedAt = propertyList["startedAt"] as? TimeInterval else {
            throw ParseError.invalidStartedAt
        }

        guard let exercisePropertyLists = propertyList["exercises"] as? [[String: Any]] else {
            throw ParseError.invalidExercises
        }

        do {
            self.exercises = try exercisePropertyLists.map(Exercise.init(propertyList:))
        } catch {
            throw ParseError.invalidExercise
        }

        self.sessionID = sessionID
        self.sessionName = sessionName
        self.startedAt = startedAt
    }
}
