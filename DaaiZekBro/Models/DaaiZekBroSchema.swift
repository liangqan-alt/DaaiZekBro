import Foundation
import SwiftData

enum DaaiZekBroSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static let models: [any PersistentModel.Type] = [
        Exercise.self,
        Template.self,
        TemplateExercise.self,
        WorkoutSession.self,
        TrainingCycle.self,
        TrainingCycleSlot.self,
        TrainingDayOverride.self,
        WorkoutSessionExerciseSnapshot.self,
        WorkoutSet.self,
    ]

    @Model
    final class Exercise {
        var name: String = ""
        var defaultRestSeconds: Int = 90
        var isUnilateral: Bool = false
        var templates: [Template] = []

        init() {}
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

        init() {}
    }

    @Model
    final class TemplateExercise {
        var template: Template?
        var exercise: Exercise?
        var orderIndex: Int = 0

        init() {}
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

        init() {}
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

        init() {}
    }

    @Model
    final class TrainingCycleSlot {
        var cycle: TrainingCycle?
        var orderIndex: Int = 0
        var kind: TrainingPlanEntryKind = TrainingPlanEntryKind.rest
        @Relationship(deleteRule: .nullify)
        var template: Template?
        var templateStableID: String = ""

        init() {}
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

        init() {}
    }

    @Model
    final class WorkoutSessionExerciseSnapshot {
        var session: WorkoutSession?
        var exercise: Exercise?
        var exerciseNameSnapshot: String = ""
        var defaultRestSecondsSnapshot: Int = 90
        var isUnilateralSnapshot: Bool = false
        var orderIndex: Int = 0

        init() {}
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

        init() {}
    }
}

enum DaaiZekBroSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 1, 0)

    static let models: [any PersistentModel.Type] = [
        Exercise.self,
        Template.self,
        TemplateExercise.self,
        WorkoutSession.self,
        TrainingCycle.self,
        TrainingCycleSlot.self,
        TrainingDayOverride.self,
        WorkoutSessionExerciseSnapshot.self,
        WorkoutSet.self,
    ]

    @Model
    final class Exercise {
        var name: String = ""
        var defaultRestSeconds: Int = 90
        var isUnilateral: Bool = false
        var templates: [Template] = []

        init() {}
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

        init() {}
    }

    @Model
    final class TemplateExercise {
        var template: Template?
        var exercise: Exercise?
        var orderIndex: Int = 0

        init() {}
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

        init() {}
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

        init() {}
    }

    @Model
    final class TrainingCycleSlot {
        var cycle: TrainingCycle?
        var orderIndex: Int = 0
        var kind: TrainingPlanEntryKind = TrainingPlanEntryKind.rest
        @Relationship(deleteRule: .nullify)
        var template: Template?
        var templateStableID: String = ""

        init() {}
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

        init() {}
    }

    @Model
    final class WorkoutSessionExerciseSnapshot {
        var session: WorkoutSession?
        var exercise: Exercise?
        var exerciseNameSnapshot: String = ""
        var defaultRestSecondsSnapshot: Int = 90
        var isUnilateralSnapshot: Bool = false
        var orderIndex: Int = 0

        init() {}
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

        init() {}
    }
}

enum DaaiZekBroSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 2, 0)

    static let models: [any PersistentModel.Type] = [
        Exercise.self,
        Template.self,
        TemplateExercise.self,
        WorkoutSession.self,
        TrainingCycle.self,
        TrainingCycleSlot.self,
        TrainingDayOverride.self,
        WorkoutSessionExerciseSnapshot.self,
        WorkoutSet.self,
    ]

    @Model
    final class Exercise {
        var name: String = ""
        var defaultRestSeconds: Int = 90
        var isUnilateral: Bool = false
        var weightUnitRawValue: String = WeightUnit.defaultUnit.rawValue
        var templates: [Template] = []

        init() {}
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

        init() {}
    }

    @Model
    final class TemplateExercise {
        var template: Template?
        var exercise: Exercise?
        var orderIndex: Int = 0

        init() {}
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

        init() {}
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

        init() {}
    }

    @Model
    final class TrainingCycleSlot {
        var cycle: TrainingCycle?
        var orderIndex: Int = 0
        var kind: TrainingPlanEntryKind = TrainingPlanEntryKind.rest
        @Relationship(deleteRule: .nullify)
        var template: Template?
        var templateStableID: String = ""

        init() {}
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

        init() {}
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

        init() {}
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

        init() {}
    }
}

enum DaaiZekBroSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 3, 0)

    static let models: [any PersistentModel.Type] = [
        Exercise.self,
        Template.self,
        TemplateExercise.self,
        WorkoutSession.self,
        TrainingCycle.self,
        TrainingCycleSlot.self,
        TrainingDayOverride.self,
        WorkoutSessionExerciseSnapshot.self,
        WorkoutSet.self,
        WatchSetSubmissionRecord.self,
    ]
}

enum DaaiZekBroMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        DaaiZekBroSchemaV1.self,
        DaaiZekBroSchemaV2.self,
        DaaiZekBroSchemaV3.self,
        DaaiZekBroSchemaV4.self,
    ]

    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: DaaiZekBroSchemaV1.self, toVersion: DaaiZekBroSchemaV2.self),
        .lightweight(fromVersion: DaaiZekBroSchemaV2.self, toVersion: DaaiZekBroSchemaV3.self),
        .lightweight(fromVersion: DaaiZekBroSchemaV3.self, toVersion: DaaiZekBroSchemaV4.self),
    ]
}

enum DaaiZekBroSchema {
    static let modelTypes = DaaiZekBroSchemaV4.models

    static func makeSchema() -> Schema {
        Schema(versionedSchema: DaaiZekBroSchemaV4.self)
    }

    static func makeModelContainer(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: DaaiZekBroMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeModelContainer(storeURL: URL) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        return try ModelContainer(
            for: schema,
            migrationPlan: DaaiZekBroMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
