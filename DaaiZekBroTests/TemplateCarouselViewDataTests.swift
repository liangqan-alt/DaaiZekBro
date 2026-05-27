import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct TemplateCarouselViewDataTests {
    @Test func ordersTemplatesBySortIndexThenName() throws {
        let alpha = Template(name: "Alpha", sortIndex: 1)
        let beta = Template(name: "Beta", sortIndex: 2)
        let gamma = Template(name: "Gamma", sortIndex: 1)

        let orderedNames = TemplateCarouselViewData
            .orderedTemplates([beta, gamma, alpha])
            .map(\.name)

        #expect(orderedNames == ["Alpha", "Gamma", "Beta"])
    }

    @Test func exerciseCountPrefersTemplateExerciseLinksAndFallsBackToLegacyRelationship() throws {
        let context = try makeInMemoryContext()
        let legacyBench = Exercise(name: "Legacy Bench")
        let legacyPress = Exercise(name: "Legacy Press")
        let linkedRow = Exercise(name: "Linked Row")
        let linkedTemplate = Template(name: "Linked", exercises: [legacyBench, legacyPress])
        let legacyTemplate = Template(name: "Legacy", exercises: [legacyBench, legacyPress])

        context.insert(legacyBench)
        context.insert(legacyPress)
        context.insert(linkedRow)
        context.insert(linkedTemplate)
        context.insert(legacyTemplate)
        context.insert(TemplateExercise(template: linkedTemplate, exercise: linkedRow, orderIndex: 0))
        try context.save()

        #expect(TemplateCarouselViewData.exerciseCount(for: linkedTemplate) == 1)
        #expect(TemplateCarouselViewData.exerciseCount(for: legacyTemplate) == 2)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
            Template.self,
            TemplateExercise.self,
            WorkoutSession.self,
            TrainingCycle.self,
            TrainingCycleSlot.self,
            TrainingDayOverride.self,
            WorkoutSessionExerciseSnapshot.self,
            WorkoutSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        return ModelContext(container)
    }
}
