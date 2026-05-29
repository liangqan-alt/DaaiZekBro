import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct WorkoutSessionExerciseIdentityTests {
    @Test func duplicateSameNameExercisesRecordAndQueryByOrderIndex() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            exercises: [
                Exercise(name: "Cable Row", defaultRestSeconds: 90, isUnilateral: false),
                Exercise(name: "Cable Row", defaultRestSeconds: 120, isUnilateral: false),
            ],
            in: context
        )

        let firstExerciseFirstSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Cable Row",
            weight: 40,
            reps: 10,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        let secondExerciseSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            exerciseName: "Cable Row",
            weight: 55,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 110),
            in: context
        )
        let firstExerciseSecondSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Cable Row",
            weight: 42.5,
            reps: 9,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 120),
            in: context
        )

        let firstExerciseSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            side: nil,
            in: context
        )
        let secondExerciseSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            side: nil,
            in: context
        )

        #expect(firstExerciseFirstSet.exerciseOrderIndex == 0)
        #expect(firstExerciseFirstSet.setIndex == 1)
        #expect(firstExerciseSecondSet.exerciseOrderIndex == 0)
        #expect(firstExerciseSecondSet.setIndex == 2)
        #expect(secondExerciseSet.exerciseOrderIndex == 1)
        #expect(secondExerciseSet.setIndex == 1)
        #expect(firstExerciseSets.map(\.weight) == [40, 42.5])
        #expect(firstExerciseSets.map(\.setIndex) == [1, 2])
        #expect(secondExerciseSets.map(\.weight) == [55])
        #expect(secondExerciseSets.map(\.setIndex) == [1])
    }

    @Test func recordingWithMissingOrderIndexDoesNotFallbackToName() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            exercises: [
                Exercise(name: "Cable Row", defaultRestSeconds: 90, isUnilateral: false),
                Exercise(name: "Cable Row", defaultRestSeconds: 120, isUnilateral: false),
            ],
            in: context
        )
        var didThrowMissingExercise = false

        do {
            _ = try WorkoutSetLogging.recordSet(
                sessionID: session.id,
                exerciseOrderIndex: 99,
                exerciseName: "Cable Row",
                weight: 40,
                reps: 10,
                rpe: nil,
                side: nil,
                in: context
            )
        } catch WorkoutSetLoggingError.exerciseNotFound {
            didThrowMissingExercise = true
        }

        #expect(didThrowMissingExercise)
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>()).isEmpty)
    }

    @Test func orderIndexSideCountsInferenceAndDeleteRenumberStayIsolatedForDuplicateNames() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            exercises: [
                Exercise(name: "Single-Leg Curl", defaultRestSeconds: 90, isUnilateral: true),
                Exercise(name: "Single-Leg Curl", defaultRestSeconds: 90, isUnilateral: true),
            ],
            in: context
        )

        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        ) == .left)

        let deletedLeftSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Single-Leg Curl",
            weight: 20,
            reps: 12,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Single-Leg Curl",
            weight: 21,
            reps: 11,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 110),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            exerciseName: "Single-Leg Curl",
            weight: 30,
            reps: 10,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 120),
            in: context
        )
        let rightSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Single-Leg Curl",
            weight: 22,
            reps: 10,
            rpe: nil,
            side: .right,
            completedAt: Date(timeIntervalSince1970: 130),
            in: context
        )

        #expect(rightSet.setIndex == 1)
        #expect(try WorkoutSetLogging.sideCounts(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        ) == WorkoutSideCounts(left: 2, right: 1))
        #expect(try WorkoutSetLogging.sideCounts(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            in: context
        ) == WorkoutSideCounts(left: 1, right: 0))
        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        ) == .right)

        try WorkoutSetLogging.deleteAndRenumber(deletedLeftSet, in: context)

        let firstExerciseLeftSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            side: .left,
            in: context
        )
        let secondExerciseLeftSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            side: .left,
            in: context
        )

        #expect(firstExerciseLeftSets.map(\.weight) == [21])
        #expect(firstExerciseLeftSets.map(\.setIndex) == [1])
        #expect(secondExerciseLeftSets.map(\.weight) == [30])
        #expect(secondExerciseLeftSets.map(\.setIndex) == [1])
        #expect(try WorkoutSetLogging.sideCounts(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        ) == WorkoutSideCounts(left: 1, right: 1))
        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        ) == .left)
    }

    @Test func recordingByOrderIndexUsesSessionSnapshotAfterTemplateEditDrift() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let benchPress = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let links = try templateExerciseLinks(for: template, in: context)

        links[0].orderIndex = 5
        links[1].orderIndex = 0
        benchPress.name = "固定器械卧推 - Edited"
        benchPress.defaultRestSeconds = 333
        try context.save()

        let descriptors = try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context)
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "固定器械卧推",
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )

        #expect(descriptors.first?.orderIndex == 0)
        #expect(descriptors.first?.name == "固定器械卧推")
        #expect(descriptors.first?.defaultRestSeconds == 120)
        #expect(set.exerciseOrderIndex == 0)
        #expect(set.exerciseNameSnapshot == "固定器械卧推")
        #expect(try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            side: nil,
            in: context
        ).map(\.weight) == [30])
    }

    private func makeSession(exercises: [Exercise], in context: ModelContext) throws -> WorkoutSession {
        let template = Template(name: "Identity Test")

        context.insert(template)

        for (index, exercise) in exercises.enumerated() {
            context.insert(exercise)
            context.insert(TemplateExercise(template: template, exercise: exercise, orderIndex: index))
        }

        try context.save()

        return try WorkoutSessionLifecycle.createSession(for: template, in: context)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

        return ModelContext(container)
    }

    private func fetchExercises(in context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\Exercise.name)]))
    }

    private func fetchTemplates(in context: ModelContext) throws -> [Template] {
        try context.fetch(FetchDescriptor<Template>())
    }

    private func fetchTemplateExercises(in context: ModelContext) throws -> [TemplateExercise] {
        try context.fetch(FetchDescriptor<TemplateExercise>())
    }

    private func template(named name: String, in context: ModelContext) throws -> Template {
        guard let template = try fetchTemplates(in: context).first(where: { $0.name == name }) else {
            throw WorkoutSessionExerciseIdentityTestError.missingTemplate(name)
        }

        return template
    }

    private func exercise(named name: String, in context: ModelContext) throws -> Exercise {
        guard let exercise = try fetchExercises(in: context).first(where: { $0.name == name }) else {
            throw WorkoutSessionExerciseIdentityTestError.missingExercise(name)
        }

        return exercise
    }

    private func templateExerciseLinks(for template: Template, in context: ModelContext) throws -> [TemplateExercise] {
        try fetchTemplateExercises(in: context)
            .filter { $0.template === template }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                return (lhs.exercise?.name ?? "") < (rhs.exercise?.name ?? "")
            }
    }
}

private enum WorkoutSessionExerciseIdentityTestError: Error {
    case missingExercise(String)
    case missingTemplate(String)
}
