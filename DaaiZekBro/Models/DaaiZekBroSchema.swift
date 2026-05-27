import Foundation
import SwiftData

enum DaaiZekBroSchema {
    static let modelTypes: [any PersistentModel.Type] = [
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

    static func makeSchema() -> Schema {
        Schema(modelTypes)
    }

    static func makeModelContainer(isStoredInMemoryOnly: Bool) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeModelContainer(storeURL: URL) throws -> ModelContainer {
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
