import Foundation
import SwiftData

enum Side: String, Codable {
    case left
    case right
}

enum WeightUnit: String, CaseIterable, Codable, Identifiable {
    case kilograms = "kg"
    case pounds = "lb"

    static let defaultUnit: WeightUnit = .kilograms
    static let storageKey = "weightUnit"
    private static let kilogramsPerPound = 0.453592

    var id: String { rawValue }
    var label: String { rawValue }

    func displayValue(fromKilograms kilograms: Double) -> Double {
        switch self {
        case .kilograms:
            return kilograms
        case .pounds:
            return kilograms / Self.kilogramsPerPound
        }
    }

    func kilograms(fromDisplayValue displayValue: Double) -> Double {
        switch self {
        case .kilograms:
            return displayValue
        case .pounds:
            return displayValue * Self.kilogramsPerPound
        }
    }
}

enum WeightDisplay {
    static func text(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 1
        formatter.maximumFractionDigits = 1

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func text(forKilograms kilograms: Double, unit: WeightUnit) -> String {
        text(unit.displayValue(fromKilograms: kilograms))
    }
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
    var sortIndex: Int = 0
    @Relationship(inverse: \Exercise.templates)
    var exercises: [Exercise] = []
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var templateExercises: [TemplateExercise] = []

    init(name: String = "", exercises: [Exercise] = [], sortIndex: Int = 0) {
        self.name = name
        self.exercises = exercises
        self.sortIndex = sortIndex
    }
}

@Model
final class TemplateExercise {
    var template: Template?
    var exercise: Exercise?
    var orderIndex: Int = 0

    init(template: Template? = nil, exercise: Exercise? = nil, orderIndex: Int = 0) {
        self.template = template
        self.exercise = exercise
        self.orderIndex = orderIndex
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
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionExerciseSnapshot.session)
    var exerciseSnapshots: [WorkoutSessionExerciseSnapshot] = []

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
final class WorkoutSessionExerciseSnapshot {
    var session: WorkoutSession?
    var exercise: Exercise?
    var exerciseNameSnapshot: String = ""
    var defaultRestSecondsSnapshot: Int = 90
    var isUnilateralSnapshot: Bool = false
    var orderIndex: Int = 0

    init(
        session: WorkoutSession? = nil,
        exercise: Exercise? = nil,
        exerciseNameSnapshot: String = "",
        defaultRestSecondsSnapshot: Int = 90,
        isUnilateralSnapshot: Bool = false,
        orderIndex: Int = 0
    ) {
        self.session = session
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.defaultRestSecondsSnapshot = defaultRestSecondsSnapshot
        self.isUnilateralSnapshot = isUnilateralSnapshot
        self.orderIndex = orderIndex
    }
}

struct WorkoutSessionExerciseDescriptor: Identifiable {
    let exercise: Exercise?
    let name: String
    let defaultRestSeconds: Int
    let isUnilateral: Bool
    let orderIndex: Int

    var id: String {
        "\(orderIndex)-\(name)"
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
