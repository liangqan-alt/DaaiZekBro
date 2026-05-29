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
}

enum DaaiZekBroMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        DaaiZekBroSchemaV1.self,
    ]

    static let stages: [MigrationStage] = []
}

enum DaaiZekBroSchema {
    static let modelTypes = DaaiZekBroSchemaV1.models

    static func makeSchema() -> Schema {
        Schema(versionedSchema: DaaiZekBroSchemaV1.self)
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
