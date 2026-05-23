import Foundation
import SwiftData

enum Side: String, Codable {
    case left
    case right
}

@Model
final class Exercise {
    var name: String = ""
    var defaultRestSeconds: Int = 90
    var isUnilateral: Bool = false
    var templates: [Template] = []

    init(name: String = "", defaultRestSeconds: Int = 90, isUnilateral: Bool = false) {
        self.name = name
        self.defaultRestSeconds = defaultRestSeconds
        self.isUnilateral = isUnilateral
    }
}

@Model
final class Template {
    var name: String = ""
    @Relationship(inverse: \Exercise.templates)
    var exercises: [Exercise] = []

    init(name: String = "", exercises: [Exercise] = []) {
        self.name = name
        self.exercises = exercises
    }
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var template: Template?
    var templateNameSnapshot: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var timezoneIdentifier: String = TimeZone.current.identifier

    init(
        id: UUID = UUID(),
        template: Template? = nil,
        templateNameSnapshot: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        timezoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.template = template
        self.templateNameSnapshot = templateNameSnapshot
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timezoneIdentifier = timezoneIdentifier
    }
}

@Model
final class WorkoutSet {
    var session: WorkoutSession?
    var exercise: Exercise?
    var exerciseNameSnapshot: String = ""
    var exerciseOrderIndex: Int = 0
    var setIndex: Int = 1
    var weight: Double = 0
    var reps: Int = 0
    var rpe: Int?
    var side: Side?
    var completedAt: Date = Date()

    init(
        session: WorkoutSession? = nil,
        exercise: Exercise? = nil,
        exerciseNameSnapshot: String = "",
        exerciseOrderIndex: Int = 0,
        setIndex: Int = 1,
        weight: Double = 0,
        reps: Int = 0,
        rpe: Int? = nil,
        side: Side? = nil,
        completedAt: Date = Date()
    ) {
        self.session = session
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.exerciseOrderIndex = exerciseOrderIndex
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.side = side
        self.completedAt = completedAt
    }
}
