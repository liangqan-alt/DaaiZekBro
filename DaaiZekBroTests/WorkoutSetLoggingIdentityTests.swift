import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct WorkoutSetLoggingIdentityTests {
    @Test func lastValuesUseExerciseIdentityAfterExerciseRename() throws {
        let context = try makeInMemoryContext()
        let (exercise, session) = try makeSession(exerciseName: "Machine Chest Press", in: context)
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: "Machine Chest Press",
            weight: 42.5,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )

        exercise.name = "Machine Press"
        try context.save()

        let lastSet = try WorkoutSetLogging.lastSet(exercise: exercise, side: nil, in: context)

        #expect(lastSet?.persistentModelID == set.persistentModelID)
        #expect(try WorkoutSetLogging.lastValues(
            exercise: exercise,
            side: nil,
            in: context
        ) == WorkoutSetValues(weight: 42.5, reps: 8))
    }

    @Test func nameFallbackWorksForSnapshotOnlySetsWithoutExerciseRelationship() throws {
        let context = try makeInMemoryContext()
        let (exercise, session) = try makeSession(exerciseName: "Standing Calf Raise", in: context)
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: "Standing Calf Raise",
            weight: 60,
            reps: 12,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )

        set.exercise = nil
        exercise.name = "Calf Raise"
        try context.save()

        #expect(try WorkoutSetLogging.lastValues(
            exerciseName: "Standing Calf Raise",
            side: nil,
            in: context
        ) == WorkoutSetValues(weight: 60, reps: 12))
    }

    private func makeSession(
        exerciseName: String,
        in context: ModelContext
    ) throws -> (Exercise, WorkoutSession) {
        let exercise = Exercise(name: exerciseName)
        let template = Template(name: "Identity Test")
        let templateExercise = TemplateExercise(template: template, exercise: exercise, orderIndex: 0)

        context.insert(exercise)
        context.insert(template)
        context.insert(templateExercise)
        try context.save()

        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        return (exercise, session)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

        return ModelContext(container)
    }
}
