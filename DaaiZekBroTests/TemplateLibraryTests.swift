import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct TemplateLibraryTests {
    @Test func createTrimsNameValidatesUniquenessAndAppendsToEnd() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let existingTemplates = try fetchTemplates(in: context)
        let previousMaxSortIndex = existingTemplates.map(\.sortIndex).max() ?? -1

        let template = try TemplateLibrary.create(name: "  Custom Push  ", in: context)

        #expect(template.name == "Custom Push")
        #expect(template.exercises.isEmpty)
        #expect(try templateExerciseLinks(for: template, in: context).isEmpty)
        #expect(template.sortIndex == previousMaxSortIndex + 1)
        #expect(try fetchTemplates(in: context).sortedByTemplateOrder().map(\.name).last == "Custom Push")

        var didThrowEmptyName = false

        do {
            _ = try TemplateLibrary.create(name: " \n ", in: context)
        } catch TemplateLibraryError.emptyName {
            didThrowEmptyName = true
        }

        var didThrowDuplicateName = false

        do {
            _ = try TemplateLibrary.create(name: "Push A", in: context)
        } catch TemplateLibraryError.duplicateName(let name) {
            didThrowDuplicateName = name == "Push A"
        }

        #expect(didThrowEmptyName)
        #expect(didThrowDuplicateName)
        #expect(try fetchTemplates(in: context).count == existingTemplates.count + 1)
    }

    @Test func renameValidatesDuplicatesExcludesSelfAndPreservesSessionSnapshot() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        try TemplateLibrary.rename(template, name: "  Push Prime  ", in: context)

        #expect(template.name == "Push Prime")
        #expect(session.templateNameSnapshot == "Push A")

        try TemplateLibrary.rename(template, name: " Push Prime ", in: context)
        #expect(template.name == "Push Prime")

        let lowercaseTemplate = try TemplateLibrary.create(name: "push prime", in: context)

        var didThrowDuplicateName = false

        do {
            try TemplateLibrary.rename(lowercaseTemplate, name: "Push Prime", in: context)
        } catch TemplateLibraryError.duplicateName(let name) {
            didThrowDuplicateName = name == "Push Prime"
        }

        #expect(didThrowDuplicateName)
        #expect(lowercaseTemplate.name == "push prime")
    }

    @Test func persistOrderWritesContiguousSortIndexes() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        var reorderedTemplates = try fetchTemplates(in: context).sortedByTemplateOrder()
        let firstTemplate = reorderedTemplates.removeFirst()
        reorderedTemplates.insert(firstTemplate, at: 3)

        try TemplateLibrary.persistOrder(reorderedTemplates, in: context)

        let persistedTemplates = try fetchTemplates(in: context).sortedByTemplateOrder()

        #expect(persistedTemplates.map(\.name) == reorderedTemplates.map(\.name))
        #expect(persistedTemplates.map(\.sortIndex) == Array(0..<persistedTemplates.count))
    }

    @Test func deleteTemplateRemovesOnlyTemplateAndTemplateLinks() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let exerciseCount = try fetchExercises(in: context).count

        #expect(try templateExerciseLinks(for: template, in: context).isEmpty == false)

        try TemplateLibrary.delete(template, in: context)

        #expect(try fetchTemplates(in: context).contains { $0.name == "Push A" } == false)
        #expect(try fetchExercises(in: context).count == exerciseCount)
        #expect(try fetchTemplateExercises(in: context).contains { $0.template?.name == "Push A" } == false)
    }

    @Test func deleteTemplateAllowsOpenSessionToContinueFromSnapshots() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        try TemplateLibrary.delete(template, in: context)

        let exerciseNames = try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context).map(\.name)
        let expectedExerciseNames = try seedExerciseNames(for: "Push A")
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: "固定器械卧推",
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            in: context
        )

        #expect(exerciseNames == expectedExerciseNames)
        #expect(set.exerciseNameSnapshot == "固定器械卧推")
        #expect(set.exerciseOrderIndex == 0)
        #expect(set.setIndex == 1)
    }

    @Test func removeExerciseFromTemplateDeletesLinkUpdatesLegacyExercisesAndReindexes() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "上斜推胸机", in: context)

        try TemplateLibrary.removeExercise(exercise, from: template, in: context)

        let remainingLinks = try templateExerciseLinks(for: template, in: context)
        let remainingNames = remainingLinks.map { $0.exercise?.name ?? "" }

        #expect(remainingNames == [
            "固定器械卧推",
            "固定器械推肩",
            "坐姿夹胸",
            "哑铃侧平举",
            "坐姿肱三头伸展机",
        ])
        #expect(remainingLinks.map(\.orderIndex) == Array(0..<remainingLinks.count))
        #expect(template.exercises.contains { $0 === exercise } == false)
    }

    @Test func removeExerciseFromTemplateRejectsOpenSessionAndLeavesOrderUnchanged() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "上斜推胸机", in: context)
        let originalNames = try templateExerciseLinks(for: template, in: context).map { $0.exercise?.name ?? "" }
        let originalOrderIndexes = try templateExerciseLinks(for: template, in: context).map(\.orderIndex)

        _ = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        var didBlockOpenSession = false

        do {
            try TemplateLibrary.removeExercise(exercise, from: template, in: context)
        } catch TemplateLibraryError.templateUsedByOpenSession {
            didBlockOpenSession = true
        }

        #expect(didBlockOpenSession)
        #expect(try templateExerciseLinks(for: template, in: context).map { $0.exercise?.name ?? "" } == originalNames)
        #expect(try templateExerciseLinks(for: template, in: context).map(\.orderIndex) == originalOrderIndexes)
        #expect(template.exercises.contains { $0 === exercise })
    }

    @Test func persistExerciseOrderWritesContiguousOrderIndexes() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        var exercises = try templateExerciseLinks(for: template, in: context).compactMap(\.exercise)
        let movedExercise = exercises.removeFirst()
        exercises.insert(movedExercise, at: 3)

        try TemplateLibrary.persistExerciseOrder(exercises, for: template, in: context)

        let persistedLinks = try templateExerciseLinks(for: template, in: context)

        #expect(persistedLinks.map { $0.exercise?.name ?? "" } == exercises.map(\.name))
        #expect(persistedLinks.map(\.orderIndex) == Array(0..<persistedLinks.count))
        #expect(Set(template.exercises.map(\.name)) == Set(exercises.map(\.name)))
    }

    @Test func persistExerciseOrderRejectsOpenSessionAndLeavesOrderUnchanged() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let originalExercises = try templateExerciseLinks(for: template, in: context).compactMap(\.exercise)
        let originalOrderIndexes = try templateExerciseLinks(for: template, in: context).map(\.orderIndex)
        var reorderedExercises = originalExercises
        let movedExercise = reorderedExercises.removeFirst()
        reorderedExercises.append(movedExercise)

        _ = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        var didBlockOpenSession = false

        do {
            try TemplateLibrary.persistExerciseOrder(reorderedExercises, for: template, in: context)
        } catch TemplateLibraryError.templateUsedByOpenSession {
            didBlockOpenSession = true
        }

        let persistedLinks = try templateExerciseLinks(for: template, in: context)

        #expect(didBlockOpenSession)
        #expect(persistedLinks.compactMap(\.exercise).map(\.name) == originalExercises.map(\.name))
        #expect(persistedLinks.map(\.orderIndex) == originalOrderIndexes)
        #expect(Set(template.exercises.map(\.name)) == Set(originalExercises.map(\.name)))
    }

    @Test func addExercisesAppendsOnlyNewExercisesAndPreservesOrder() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let existingExercise = try exercise(named: "固定器械卧推", in: context)
        let hackSquat = try ExerciseLibrary.create(
            name: "Hack Squat",
            defaultRestSeconds: 120,
            isUnilateral: false,
            in: context
        )
        let calfRaise = try ExerciseLibrary.create(
            name: "Calf Raise",
            defaultRestSeconds: 60,
            isUnilateral: false,
            in: context
        )
        let originalNames = try templateExerciseLinks(for: template, in: context).map { $0.exercise?.name ?? "" }

        let appendedExercises = try TemplateLibrary.appendExercises(
            [existingExercise, hackSquat, calfRaise],
            to: template,
            in: context
        )
        let persistedLinks = try templateExerciseLinks(for: template, in: context)

        #expect(appendedExercises.map(\.name) == ["Hack Squat", "Calf Raise"])
        #expect(persistedLinks.map { $0.exercise?.name ?? "" } == originalNames + ["Hack Squat", "Calf Raise"])
        #expect(persistedLinks.map(\.orderIndex) == Array(0..<persistedLinks.count))
        #expect(WorkoutSessionLifecycle.orderedExercises(for: template).map(\.name) == originalNames + ["Hack Squat", "Calf Raise"])
    }

    @Test func addExercisesToEmptyTemplateStartsOrderAtZero() throws {
        let context = try makeInMemoryContext()

        let template = try TemplateLibrary.create(name: "Custom Legs", in: context)
        let legPress = try ExerciseLibrary.create(
            name: "Leg Press",
            defaultRestSeconds: 150,
            isUnilateral: false,
            in: context
        )
        let splitSquat = try ExerciseLibrary.create(
            name: "Split Squat",
            defaultRestSeconds: 90,
            isUnilateral: true,
            in: context
        )

        let appendedExercises = try TemplateLibrary.appendExercises(
            [legPress, splitSquat],
            to: template,
            in: context
        )
        let persistedLinks = try templateExerciseLinks(for: template, in: context)

        #expect(appendedExercises.map(\.name) == ["Leg Press", "Split Squat"])
        #expect(persistedLinks.map { $0.exercise?.name ?? "" } == ["Leg Press", "Split Squat"])
        #expect(persistedLinks.map(\.orderIndex) == [0, 1])
        #expect(Set(template.exercises.map(\.name)) == Set(["Leg Press", "Split Squat"]))
    }

    @Test func addExercisesDedupsRepeatedSelection() throws {
        let context = try makeInMemoryContext()

        let template = try TemplateLibrary.create(name: "Custom Push", in: context)
        let benchPress = try ExerciseLibrary.create(
            name: "Bench Press",
            defaultRestSeconds: 120,
            isUnilateral: false,
            in: context
        )
        let shoulderPress = try ExerciseLibrary.create(
            name: "Shoulder Press",
            defaultRestSeconds: 90,
            isUnilateral: false,
            in: context
        )

        let appendedExercises = try TemplateLibrary.appendExercises(
            [benchPress, benchPress, shoulderPress, benchPress],
            to: template,
            in: context
        )
        let persistedLinks = try templateExerciseLinks(for: template, in: context)

        #expect(appendedExercises.map(\.name) == ["Bench Press", "Shoulder Press"])
        #expect(persistedLinks.map { $0.exercise?.name ?? "" } == ["Bench Press", "Shoulder Press"])
        #expect(persistedLinks.map(\.orderIndex) == [0, 1])
    }

    @Test func addExercisesRejectsOpenSessionAndLeavesTemplateUnchanged() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let newExercise = try ExerciseLibrary.create(
            name: "Cable Press",
            defaultRestSeconds: 90,
            isUnilateral: false,
            in: context
        )
        let originalNames = try templateExerciseLinks(for: template, in: context).map { $0.exercise?.name ?? "" }
        let originalOrderIndexes = try templateExerciseLinks(for: template, in: context).map(\.orderIndex)

        _ = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        var didBlockOpenSession = false

        do {
            _ = try TemplateLibrary.appendExercises([newExercise], to: template, in: context)
        } catch TemplateLibraryError.templateUsedByOpenSession {
            didBlockOpenSession = true
        }

        let persistedLinks = try templateExerciseLinks(for: template, in: context)

        #expect(didBlockOpenSession)
        #expect(persistedLinks.map { $0.exercise?.name ?? "" } == originalNames)
        #expect(persistedLinks.map(\.orderIndex) == originalOrderIndexes)
        #expect(WorkoutSessionLifecycle.orderedExercises(for: template).map(\.name) == originalNames)
    }

    @Test func templateNameSavePolicyRejectsBlankAndMissingEditedTemplate() {
        #expect(TemplateNameEditorSavePolicy.canSave(
            isNewTemplate: true,
            hasTemplate: false,
            name: " Custom Push "
        ))
        #expect(TemplateNameEditorSavePolicy.canSave(
            isNewTemplate: false,
            hasTemplate: true,
            name: "Custom Push"
        ))
        #expect(TemplateNameEditorSavePolicy.canSave(
            isNewTemplate: false,
            hasTemplate: false,
            name: "Custom Push"
        ) == false)
        #expect(TemplateNameEditorSavePolicy.canSave(
            isNewTemplate: true,
            hasTemplate: false,
            name: " \n "
        ) == false)
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

    private func exercise(named name: String, in context: ModelContext) throws -> Exercise {
        guard let exercise = try fetchExercises(in: context).first(where: { $0.name == name }) else {
            throw TemplateLibraryTestError.missingExercise(name)
        }

        return exercise
    }

    private func template(named name: String, in context: ModelContext) throws -> Template {
        guard let template = try fetchTemplates(in: context).first(where: { $0.name == name }) else {
            throw TemplateLibraryTestError.missingTemplate(name)
        }

        return template
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

    private func seedExerciseNames(for templateName: String) throws -> [String] {
        guard let seedTemplate = SeedData.templateExerciseNames.first(where: { $0.name == templateName }) else {
            throw TemplateLibraryTestError.missingTemplate(templateName)
        }

        return seedTemplate.exerciseNames
    }
}

private extension Array where Element == Template {
    func sortedByTemplateOrder() -> [Template] {
        sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.name < rhs.name
        }
    }
}

private enum TemplateLibraryTestError: Error {
    case missingExercise(String)
    case missingTemplate(String)
}
