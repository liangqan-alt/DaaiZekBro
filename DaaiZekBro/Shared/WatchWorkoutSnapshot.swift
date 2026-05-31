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
        case invalidLeftCompletedSetCount
        case invalidRightCompletedSetCount
        case invalidWeightUnit
        case invalidIsUnilateral
        case invalidDefaultRestSeconds
        case invalidLastSetReference
        case invalidLastSetWeight
        case invalidLastSetReps
        case invalidLastSetSource
    }

    struct LastSetReference: Equatable {
        let weight: Double
        let reps: Int
        let source: String

        nonisolated var propertyList: [String: Any] {
            [
                "weight": weight,
                "reps": reps,
                "source": source,
            ]
        }

        nonisolated init(weight: Double, reps: Int, source: String) {
            self.weight = weight
            self.reps = reps
            self.source = source
        }

        nonisolated init(propertyList: [String: Any]) throws {
            guard let weight = propertyList["weight"] as? Double,
                  weight.isFinite,
                  weight >= 0 else {
                throw ParseError.invalidLastSetWeight
            }

            guard let reps = propertyList["reps"] as? Int,
                  reps >= 1 else {
                throw ParseError.invalidLastSetReps
            }

            guard let source = propertyList["source"] as? String,
                  source == "currentSession" || source == "history" else {
                throw ParseError.invalidLastSetSource
            }

            self.weight = weight
            self.reps = reps
            self.source = source
        }
    }

    struct Exercise: Equatable {
        let exerciseOrderIndex: Int
        let name: String
        let completedSetCount: Int
        let leftCompletedSetCount: Int
        let rightCompletedSetCount: Int
        let weightUnit: String
        let isUnilateral: Bool
        let defaultRestSeconds: Int
        let lastSetReference: LastSetReference?

        nonisolated var propertyList: [String: Any] {
            var propertyList: [String: Any] = [
                "exerciseOrderIndex": exerciseOrderIndex,
                "name": name,
                "completedSetCount": completedSetCount,
                "leftCompletedSetCount": leftCompletedSetCount,
                "rightCompletedSetCount": rightCompletedSetCount,
                "weightUnit": weightUnit,
                "isUnilateral": isUnilateral,
                "defaultRestSeconds": defaultRestSeconds,
            ]

            if let lastSetReference {
                propertyList["lastSetReference"] = lastSetReference.propertyList
            }

            return propertyList
        }

        nonisolated init(
            exerciseOrderIndex: Int,
            name: String,
            completedSetCount: Int,
            weightUnit: String,
            isUnilateral: Bool,
            defaultRestSeconds: Int,
            leftCompletedSetCount: Int = 0,
            rightCompletedSetCount: Int = 0,
            lastSetReference: LastSetReference? = nil
        ) {
            self.exerciseOrderIndex = exerciseOrderIndex
            self.name = name
            self.completedSetCount = completedSetCount
            self.leftCompletedSetCount = leftCompletedSetCount
            self.rightCompletedSetCount = rightCompletedSetCount
            self.weightUnit = weightUnit
            self.isUnilateral = isUnilateral
            self.defaultRestSeconds = defaultRestSeconds
            self.lastSetReference = lastSetReference
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

            let leftCompletedSetCount = propertyList["leftCompletedSetCount"] as? Int ?? 0
            guard leftCompletedSetCount >= 0 else {
                throw ParseError.invalidLeftCompletedSetCount
            }

            let rightCompletedSetCount = propertyList["rightCompletedSetCount"] as? Int ?? 0
            guard rightCompletedSetCount >= 0 else {
                throw ParseError.invalidRightCompletedSetCount
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

            let lastSetReference: LastSetReference?
            if let referencePropertyList = propertyList["lastSetReference"] {
                guard let referencePropertyList = referencePropertyList as? [String: Any] else {
                    throw ParseError.invalidLastSetReference
                }

                do {
                    lastSetReference = try LastSetReference(propertyList: referencePropertyList)
                } catch {
                    throw ParseError.invalidLastSetReference
                }
            } else {
                lastSetReference = nil
            }

            self.exerciseOrderIndex = exerciseOrderIndex
            self.name = name
            self.completedSetCount = completedSetCount
            self.leftCompletedSetCount = leftCompletedSetCount
            self.rightCompletedSetCount = rightCompletedSetCount
            self.weightUnit = weightUnit
            self.isUnilateral = isUnilateral
            self.defaultRestSeconds = defaultRestSeconds
            self.lastSetReference = lastSetReference
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
