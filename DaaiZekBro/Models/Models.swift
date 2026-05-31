import Foundation
import SwiftData

enum Side: String, Codable {
    case left
    case right
}

enum WeightUnit: String, CaseIterable, Codable, Identifiable {
    case kilograms = "kg"
    case pounds = "lb"

    nonisolated static let defaultUnit: WeightUnit = .kilograms
    private nonisolated static let kilogramsPerPound = 0.453592

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

enum TrainingPlanEntryKind: String, Codable, Hashable {
    case workout
    case rest
}

@Model
final class Exercise {
    var name: String = ""
    var defaultRestSeconds: Int = 90
    var isUnilateral: Bool = false
    var weightUnitRawValue: String = WeightUnit.defaultUnit.rawValue
    var templates: [Template] = []

    var weightUnit: WeightUnit {
        get {
            WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit
        }
        set {
            weightUnitRawValue = newValue.rawValue
        }
    }

    init(
        name: String = "",
        defaultRestSeconds: Int = 90,
        isUnilateral: Bool = false,
        weightUnit: WeightUnit = .defaultUnit
    ) {
        self.name = name
        self.defaultRestSeconds = defaultRestSeconds
        self.isUnilateral = isUnilateral
        self.weightUnitRawValue = weightUnit.rawValue
    }
}

@Model
final class Template {
    var name: String = ""
    var sortIndex: Int = 0
    var stableID: String = ""
    var colorHex: String?
    @Relationship(inverse: \Exercise.templates)
    var exercises: [Exercise] = []
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var templateExercises: [TemplateExercise] = []

    init(
        name: String = "",
        exercises: [Exercise] = [],
        sortIndex: Int = 0,
        stableID: String = UUID().uuidString,
        colorHex: String? = nil
    ) {
        self.name = name
        self.exercises = exercises
        self.sortIndex = sortIndex
        self.stableID = stableID
        self.colorHex = colorHex
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

extension Sequence where Element == TemplateExercise {
    func sortedByTemplateExerciseOrder() -> [TemplateExercise] {
        sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }

            return (lhs.exercise?.name ?? "") < (rhs.exercise?.name ?? "")
        }
    }
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var template: Template?
    var templateNameSnapshot: String = ""
    var templateStableIDSnapshot: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var timezoneIdentifier: String = TimeZone.current.identifier
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSessionExerciseSnapshot.session)
    var exerciseSnapshots: [WorkoutSessionExerciseSnapshot] = []
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.session)
    var sets: [WorkoutSet] = []

    init(
        id: UUID = UUID(),
        template: Template? = nil,
        templateNameSnapshot: String = "",
        templateStableIDSnapshot: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        timezoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.template = template
        self.templateNameSnapshot = templateNameSnapshot
        self.templateStableIDSnapshot = templateStableIDSnapshot
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timezoneIdentifier = timezoneIdentifier
    }
}

@Model
final class TrainingCycle {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var timezoneIdentifier: String = TimeZone.current.identifier
    @Relationship(deleteRule: .cascade, inverse: \TrainingCycleSlot.cycle)
    var slots: [TrainingCycleSlot] = []
    @Relationship(deleteRule: .cascade, inverse: \TrainingDayOverride.cycle)
    var dayOverrides: [TrainingDayOverride] = []

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        timezoneIdentifier: String = TimeZone.current.identifier,
        slots: [TrainingCycleSlot] = [],
        dayOverrides: [TrainingDayOverride] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.timezoneIdentifier = timezoneIdentifier
        self.slots = slots
        self.dayOverrides = dayOverrides
    }
}

@Model
final class TrainingCycleSlot {
    var cycle: TrainingCycle?
    var orderIndex: Int = 0
    var kind: TrainingPlanEntryKind = TrainingPlanEntryKind.rest
    @Relationship(deleteRule: .nullify)
    var template: Template?
    var templateStableID: String = ""

    init(
        cycle: TrainingCycle? = nil,
        orderIndex: Int = 0,
        kind: TrainingPlanEntryKind = .rest,
        template: Template? = nil,
        templateStableID: String? = nil
    ) {
        self.cycle = cycle
        self.orderIndex = orderIndex
        self.kind = kind
        self.template = template
        self.templateStableID = templateStableID ?? (kind == .workout ? template?.stableID ?? "" : "")
    }

    var isRestDay: Bool {
        kind == .rest
    }

    var isInvalidPlan: Bool {
        kind == .workout && template == nil && templateStableID.isEmpty == false
    }
}

@Model
final class TrainingDayOverride {
    var cycle: TrainingCycle?
    var localDateKey: String = ""
    @Attribute(.unique)
    var cycleDateKey: String = ""
    var kind: TrainingPlanEntryKind = TrainingPlanEntryKind.rest
    @Relationship(deleteRule: .nullify)
    var template: Template?
    var templateStableID: String = ""

    init(
        cycle: TrainingCycle? = nil,
        localDateKey: String = "",
        kind: TrainingPlanEntryKind = .rest,
        template: Template? = nil,
        templateStableID: String? = nil
    ) {
        self.cycle = cycle
        self.localDateKey = localDateKey
        self.cycleDateKey = cycle.map { Self.cycleDateKey(cycleID: $0.id, localDateKey: localDateKey) } ?? localDateKey
        self.kind = kind
        self.template = template
        self.templateStableID = templateStableID ?? (kind == .workout ? template?.stableID ?? "" : "")
    }

    static func cycleDateKey(cycleID: UUID, localDateKey: String) -> String {
        "\(cycleID.uuidString)|\(localDateKey)"
    }

    @MainActor
    static func existing(cycleDateKey targetKey: String, in context: ModelContext) throws -> TrainingDayOverride? {
        var descriptor = FetchDescriptor<TrainingDayOverride>(
            predicate: #Predicate<TrainingDayOverride> { dayOverride in
                dayOverride.cycleDateKey == targetKey
            }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    var isRestDay: Bool {
        kind == .rest
    }

    var isInvalidPlan: Bool {
        kind == .workout && template == nil && templateStableID.isEmpty == false
    }

    @MainActor
    @discardableResult
    static func upsert(
        cycle: TrainingCycle,
        localDateKey: String,
        kind: TrainingPlanEntryKind,
        template: Template?,
        in context: ModelContext
    ) throws -> TrainingDayOverride {
        let cycleDateKey = TrainingDayOverride.cycleDateKey(cycleID: cycle.id, localDateKey: localDateKey)

        if let existingOverride = try existing(cycleDateKey: cycleDateKey, in: context) {
            existingOverride.cycle = cycle
            existingOverride.localDateKey = localDateKey
            existingOverride.kind = kind
            existingOverride.template = template
            existingOverride.templateStableID = kind == .workout ? template?.stableID ?? existingOverride.templateStableID : ""
            try context.save()
            return existingOverride
        }

        let dayOverride = TrainingDayOverride(
            cycle: cycle,
            localDateKey: localDateKey,
            kind: kind,
            template: template
        )

        context.insert(dayOverride)
        try context.save()

        return dayOverride
    }
}

@Model
final class WorkoutSessionExerciseSnapshot {
    var session: WorkoutSession?
    var exercise: Exercise?
    var exerciseNameSnapshot: String = ""
    var defaultRestSecondsSnapshot: Int = 90
    var isUnilateralSnapshot: Bool = false
    var weightUnitRawValueSnapshot: String = WeightUnit.defaultUnit.rawValue
    var orderIndex: Int = 0

    var weightUnit: WeightUnit {
        get {
            WeightUnit(rawValue: weightUnitRawValueSnapshot) ?? .defaultUnit
        }
        set {
            weightUnitRawValueSnapshot = newValue.rawValue
        }
    }

    init(
        session: WorkoutSession? = nil,
        exercise: Exercise? = nil,
        exerciseNameSnapshot: String = "",
        defaultRestSecondsSnapshot: Int = 90,
        isUnilateralSnapshot: Bool = false,
        weightUnit: WeightUnit = .defaultUnit,
        orderIndex: Int = 0
    ) {
        self.session = session
        self.exercise = exercise
        self.exerciseNameSnapshot = exerciseNameSnapshot
        self.defaultRestSecondsSnapshot = defaultRestSecondsSnapshot
        self.isUnilateralSnapshot = isUnilateralSnapshot
        self.weightUnitRawValueSnapshot = weightUnit.rawValue
        self.orderIndex = orderIndex
    }
}

struct WorkoutSessionExerciseDescriptor: Identifiable {
    let exercise: Exercise?
    let name: String
    let defaultRestSeconds: Int
    let isUnilateral: Bool
    let weightUnit: WeightUnit
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

enum WatchSetSubmissionRecordStatus: String, Codable, CaseIterable {
    case saved
    case needsUserAction
    case discarded
}

enum WatchSetSubmissionRecordReason: String, Codable, CaseIterable {
    case sessionNotFound
    case exerciseNotFound
    case syncTimeout
}

@Model
final class WatchSetSubmissionRecord {
    @Attribute(.unique)
    var clientSubmissionID: String = ""
    var originalSessionID: String = ""
    var originalSessionName: String = ""
    var originalSessionStartedAt: Date?
    var exerciseOrderIndex: Int = 0
    var exerciseName: String = ""
    var weight: Double = 0
    var weightUnitRawValue: String = WeightUnit.defaultUnit.rawValue
    var reps: Int = 0
    var rpe: Int?
    var sideRawValue: String?
    var completedAt: Date = Date()
    var submittedAt: Date = Date()
    var statusRawValue: String = WatchSetSubmissionRecordStatus.needsUserAction.rawValue
    var reasonRawValue: String?
    var message: String = ""
    var savedSetIndex: Int?
    var completedSetCount: Int?
    var resolvedSessionID: String?
    var resolvedExerciseOrderIndex: Int?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var status: WatchSetSubmissionRecordStatus {
        get {
            WatchSetSubmissionRecordStatus(rawValue: statusRawValue) ?? .needsUserAction
        }
        set {
            statusRawValue = newValue.rawValue
        }
    }

    var reason: WatchSetSubmissionRecordReason? {
        get {
            reasonRawValue.flatMap(WatchSetSubmissionRecordReason.init(rawValue:))
        }
        set {
            reasonRawValue = newValue?.rawValue
        }
    }

    var weightUnit: WeightUnit {
        get {
            WeightUnit(rawValue: weightUnitRawValue) ?? .defaultUnit
        }
        set {
            weightUnitRawValue = newValue.rawValue
        }
    }

    var side: Side? {
        get {
            sideRawValue.flatMap(Side.init(rawValue:))
        }
        set {
            sideRawValue = newValue?.rawValue
        }
    }

    init(
        clientSubmissionID: String = "",
        originalSessionID: String = "",
        originalSessionName: String = "",
        originalSessionStartedAt: Date? = nil,
        exerciseOrderIndex: Int = 0,
        exerciseName: String = "",
        weight: Double = 0,
        weightUnit: WeightUnit = .defaultUnit,
        reps: Int = 0,
        rpe: Int? = nil,
        side: Side? = nil,
        completedAt: Date = Date(),
        submittedAt: Date = Date(),
        status: WatchSetSubmissionRecordStatus = .needsUserAction,
        reason: WatchSetSubmissionRecordReason? = nil,
        message: String = "",
        savedSetIndex: Int? = nil,
        completedSetCount: Int? = nil,
        resolvedSessionID: UUID? = nil,
        resolvedExerciseOrderIndex: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.clientSubmissionID = clientSubmissionID
        self.originalSessionID = originalSessionID
        self.originalSessionName = originalSessionName
        self.originalSessionStartedAt = originalSessionStartedAt
        self.exerciseOrderIndex = exerciseOrderIndex
        self.exerciseName = exerciseName
        self.weight = weight
        self.weightUnitRawValue = weightUnit.rawValue
        self.reps = reps
        self.rpe = rpe
        self.sideRawValue = side?.rawValue
        self.completedAt = completedAt
        self.submittedAt = submittedAt
        self.statusRawValue = status.rawValue
        self.reasonRawValue = reason?.rawValue
        self.message = message
        self.savedSetIndex = savedSetIndex
        self.completedSetCount = completedSetCount
        self.resolvedSessionID = resolvedSessionID?.uuidString
        self.resolvedExerciseOrderIndex = resolvedExerciseOrderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
