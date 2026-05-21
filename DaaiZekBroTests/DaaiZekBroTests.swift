//
//  DaaiZekBroTests.swift
//  DaaiZekBroTests
//
//  Created by liangqan on 2026/5/20.
//

import Foundation
import Testing
import SwiftData
@testable import DaaiZekBro

@MainActor
struct DaaiZekBroTests {

    @Test func seedDataWritesExpectedRecords() throws {
        let context = try makeInMemoryContext()

        try SeedData.writeAndDedup(in: context)

        let exercises = try fetchExercises(in: context)
        let templates = try fetchTemplates(in: context)

        #expect(exercises.count == 19)
        #expect(templates.count == 6)
        #expect(templateCounts(templates) == [
            "Legs A": 5,
            "Legs B": 6,
            "Pull A": 5,
            "Pull B": 5,
            "Push A": 6,
            "Push B": 6,
        ])
    }

    @Test func seedDataWriteIsIdempotent() throws {
        let context = try makeInMemoryContext()

        try SeedData.writeAndDedup(in: context)
        try SeedData.writeAndDedup(in: context)

        #expect(try fetchExercises(in: context).count == 19)
        #expect(try fetchTemplates(in: context).count == 6)
    }

    @Test func onlyKneelingSingleLegCurlIsUnilateral() throws {
        let context = try makeInMemoryContext()

        try SeedData.writeAndDedup(in: context)

        let exercises = try fetchExercises(in: context)
        let unilateralExercises = exercises.filter(\.isUnilateral).map(\.name)

        #expect(unilateralExercises == ["跪姿单腿腿弯举"])
        #expect(exercises.filter { !$0.isUnilateral }.count == 18)
    }

    @Test func workoutSessionCreatesUUIDByDefault() {
        let session = WorkoutSession()

        #expect(session.id.uuidString.isEmpty == false)
    }

    @Test func seedDataDedupsManuallyInsertedDuplicates() throws {
        let context = try makeInMemoryContext()
        let duplicateExercises = SeedData.exercises() + SeedData.exercises()

        for exercise in duplicateExercises {
            context.insert(exercise)
        }

        let firstExerciseSet = Array(duplicateExercises.prefix(19))
        for template in SeedData.templates(allExercises: firstExerciseSet) {
            context.insert(template)
        }
        for template in SeedData.templates(allExercises: Array(duplicateExercises.suffix(19))) {
            context.insert(template)
        }

        try context.save()
        try SeedData.writeAndDedup(in: context)

        let exercises = try fetchExercises(in: context)
        let templates = try fetchTemplates(in: context)

        #expect(exercises.count == 19)
        #expect(Set(exercises.map(\.name)).count == 19)
        #expect(templates.count == 6)
        #expect(Set(templates.map(\.name)).count == 6)
        #expect(templateCounts(templates) == [
            "Legs A": 5,
            "Legs B": 6,
            "Pull A": 5,
            "Pull B": 5,
            "Push A": 6,
            "Push B": 6,
        ])
        #expect(templates.flatMap(\.exercises).allSatisfy { exercise in
            exercises.contains { $0.name == exercise.name }
        })
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
            Template.self,
            WorkoutSession.self,
            WorkoutSet.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        return ModelContext(container)
    }

    private func fetchExercises(in context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\Exercise.name)]))
    }

    private func fetchTemplates(in context: ModelContext) throws -> [Template] {
        try context.fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.name)]))
    }

    private func templateCounts(_ templates: [Template]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: templates.map { ($0.name, $0.exercises.count) })
    }
}
