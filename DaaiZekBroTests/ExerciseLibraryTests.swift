import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct ExerciseLibraryTests {
    @Test func editorSavePolicyRejectsMissingEditedExercise() {
        #expect(ExerciseEditorSavePolicy.canSave(
            isNewExercise: true,
            hasExercise: false,
            name: " Hack Squat ",
            defaultRestSeconds: ExerciseLibrary.minimumRestSeconds
        ))
        #expect(ExerciseEditorSavePolicy.canSave(
            isNewExercise: false,
            hasExercise: true,
            name: "Hack Squat",
            defaultRestSeconds: ExerciseLibrary.minimumRestSeconds
        ))
        #expect(ExerciseEditorSavePolicy.canSave(
            isNewExercise: false,
            hasExercise: false,
            name: "Hack Squat",
            defaultRestSeconds: ExerciseLibrary.minimumRestSeconds
        ) == false)
        #expect(ExerciseEditorSavePolicy.canSave(
            isNewExercise: true,
            hasExercise: false,
            name: " \n ",
            defaultRestSeconds: ExerciseLibrary.minimumRestSeconds
        ) == false)
        #expect(ExerciseEditorSavePolicy.canSave(
            isNewExercise: true,
            hasExercise: false,
            name: "Hack Squat",
            defaultRestSeconds: ExerciseLibrary.minimumRestSeconds - 1
        ) == false)
    }

    @Test func createTrimsNameAndRejectsInvalidInput() throws {
        let context = try makeInMemoryContext()

        let exercise = try ExerciseLibrary.create(
            name: "  Bulgarian Split Squat  ",
            defaultRestSeconds: ExerciseLibrary.minimumRestSeconds,
            isUnilateral: true,
            in: context
        )

        #expect(exercise.name == "Bulgarian Split Squat")
        #expect(exercise.defaultRestSeconds == ExerciseLibrary.minimumRestSeconds)
        #expect(exercise.isUnilateral)

        var didThrowEmptyName = false

        do {
            _ = try ExerciseLibrary.create(
                name: " \n ",
                defaultRestSeconds: ExerciseLibrary.minimumRestSeconds,
                isUnilateral: false,
                in: context
            )
        } catch ExerciseLibraryError.emptyName {
            didThrowEmptyName = true
        }

        var didThrowInvalidRest = false

        do {
            _ = try ExerciseLibrary.create(
                name: "Hack Squat",
                defaultRestSeconds: ExerciseLibrary.minimumRestSeconds - 1,
                isUnilateral: false,
                in: context
            )
        } catch ExerciseLibraryError.invalidDefaultRestSeconds(let seconds) {
            didThrowInvalidRest = seconds == ExerciseLibrary.minimumRestSeconds - 1
        }

        #expect(didThrowEmptyName)
        #expect(didThrowInvalidRest)
        #expect(try fetchExercises(in: context).map(\.name) == ["Bulgarian Split Squat"])
    }

    @Test func duplicateValidationIsExactCaseSensitiveAndExcludesSelfOnEdit() throws {
        let context = try makeInMemoryContext()
        let exercise = try ExerciseLibrary.create(
            name: "Bench Press",
            defaultRestSeconds: 90,
            isUnilateral: false,
            in: context
        )

        try ExerciseLibrary.update(
            exercise,
            name: " Bench Press ",
            defaultRestSeconds: 120,
            isUnilateral: false,
            in: context
        )

        let lowercaseExercise = try ExerciseLibrary.create(
            name: "bench press",
            defaultRestSeconds: 90,
            isUnilateral: false,
            in: context
        )

        var didThrowDuplicateCreate = false

        do {
            _ = try ExerciseLibrary.create(
                name: "Bench Press",
                defaultRestSeconds: 90,
                isUnilateral: false,
                in: context
            )
        } catch ExerciseLibraryError.duplicateName(let name) {
            didThrowDuplicateCreate = name == "Bench Press"
        }

        var didThrowDuplicateUpdate = false

        do {
            try ExerciseLibrary.update(
                lowercaseExercise,
                name: "Bench Press",
                defaultRestSeconds: 90,
                isUnilateral: false,
                in: context
            )
        } catch ExerciseLibraryError.duplicateName(let name) {
            didThrowDuplicateUpdate = name == "Bench Press"
        }

        #expect(didThrowDuplicateCreate)
        #expect(didThrowDuplicateUpdate)
        #expect(try fetchExercises(in: context).map(\.name).sorted() == ["Bench Press", "bench press"])
    }

    @Test func openSessionBlocksRenameUnilateralChangeAndDeleteButAllowsRestOnlyUpdate() throws {
        let context = try makeInMemoryContext()
        let exercise = try ExerciseLibrary.create(
            name: "Leg Press",
            defaultRestSeconds: 90,
            isUnilateral: false,
            in: context
        )
        let template = Template(name: "Legs", exercises: [exercise])

        context.insert(template)
        try context.save()

        _ = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        var didBlockRename = false

        do {
            try ExerciseLibrary.update(
                exercise,
                name: "Machine Leg Press",
                defaultRestSeconds: 90,
                isUnilateral: false,
                in: context
            )
        } catch ExerciseLibraryError.exerciseUsedByOpenSession {
            didBlockRename = true
        }

        var didBlockUnilateralChange = false

        do {
            try ExerciseLibrary.update(
                exercise,
                name: "Leg Press",
                defaultRestSeconds: 90,
                isUnilateral: true,
                in: context
            )
        } catch ExerciseLibraryError.exerciseUsedByOpenSession {
            didBlockUnilateralChange = true
        }

        try ExerciseLibrary.update(
            exercise,
            name: "Leg Press",
            defaultRestSeconds: 120,
            isUnilateral: false,
            in: context
        )

        var didBlockDelete = false

        do {
            try ExerciseLibrary.delete(exercise, in: context)
        } catch ExerciseLibraryError.exerciseUsedByOpenSession {
            didBlockDelete = true
        }

        #expect(didBlockRename)
        #expect(didBlockUnilateralChange)
        #expect(didBlockDelete)
        #expect(exercise.name == "Leg Press")
        #expect(exercise.defaultRestSeconds == 120)
        #expect(exercise.isUnilateral == false)
        #expect(try fetchExercises(in: context).count == 1)
    }

    @Test func deleteRemovesTemplateLinksReindexesAndPreservesSessionSnapshots() throws {
        let context = try makeInMemoryContext()
        let firstExercise = try ExerciseLibrary.create(
            name: "Chest Press",
            defaultRestSeconds: 90,
            isUnilateral: false,
            in: context
        )
        let deletedExercise = try ExerciseLibrary.create(
            name: "Cable Fly",
            defaultRestSeconds: 75,
            isUnilateral: false,
            in: context
        )
        let lastExercise = try ExerciseLibrary.create(
            name: "Triceps Pressdown",
            defaultRestSeconds: 60,
            isUnilateral: false,
            in: context
        )
        let template = Template(name: "Push", exercises: [firstExercise, deletedExercise, lastExercise])

        context.insert(template)
        context.insert(TemplateExercise(template: template, exercise: firstExercise, orderIndex: 0))
        context.insert(TemplateExercise(template: template, exercise: deletedExercise, orderIndex: 1))
        context.insert(TemplateExercise(template: template, exercise: lastExercise, orderIndex: 2))
        try context.save()

        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: deletedExercise.name,
            weight: 20,
            reps: 12,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 1_000),
            in: context
        )
        try WorkoutSessionLifecycle.end(session, in: context)

        try ExerciseLibrary.delete(deletedExercise, in: context)

        let remainingLinks = try templateExerciseLinks(for: template, in: context)
        let snapshots = try fetchSessionExerciseSnapshots(in: context)
        let sets = try fetchSets(in: context)

        #expect(try fetchExercises(in: context).map(\.name).sorted() == ["Chest Press", "Triceps Pressdown"])
        #expect(template.exercises.map(\.name).sorted() == ["Chest Press", "Triceps Pressdown"])
        #expect(remainingLinks.map { $0.exercise?.name ?? "" } == ["Chest Press", "Triceps Pressdown"])
        #expect(remainingLinks.map(\.orderIndex) == [0, 1])
        #expect(snapshots.map(\.exerciseNameSnapshot).sorted() == [
            "Cable Fly",
            "Chest Press",
            "Triceps Pressdown",
        ])
        #expect(sets.count == 1)
        #expect(sets[0].id == set.id)
        #expect(sets[0].exerciseNameSnapshot == "Cable Fly")
        #expect(sets[0].weight == 20)
        #expect(sets[0].reps == 12)
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

    private func fetchExercises(in context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\Exercise.name)]))
    }

    private func fetchTemplateExercises(in context: ModelContext) throws -> [TemplateExercise] {
        try context.fetch(FetchDescriptor<TemplateExercise>())
    }

    private func fetchSessionExerciseSnapshots(in context: ModelContext) throws -> [WorkoutSessionExerciseSnapshot] {
        try context.fetch(FetchDescriptor<WorkoutSessionExerciseSnapshot>())
    }

    private func fetchSets(in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(FetchDescriptor<WorkoutSet>())
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
