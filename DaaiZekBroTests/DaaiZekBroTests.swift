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

    @Test func creatingSessionCopiesTemplateMetadata() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let startedAt = Date(timeIntervalSince1970: 1_800)

        guard let timeZone = TimeZone(identifier: "Asia/Shanghai") else {
            throw TestLookupError.missingTimeZone("Asia/Shanghai")
        }

        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: startedAt,
            timeZone: timeZone
        )

        #expect(session.template?.name == "Push A")
        #expect(session.templateNameSnapshot == "Push A")
        #expect(session.startedAt == startedAt)
        #expect(session.timezoneIdentifier == "Asia/Shanghai")
        #expect(session.endedAt == nil)
        #expect(try openSessionCount(in: context) == 1)
    }

    @Test func creatingSessionWhileOneIsOpenThrows() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let pushTemplate = try template(named: "Push A", in: context)
        let pullTemplate = try template(named: "Pull A", in: context)

        _ = try WorkoutSessionLifecycle.createSession(for: pushTemplate, in: context)
        var didThrowOpenSessionError = false

        do {
            _ = try WorkoutSessionLifecycle.createSession(for: pullTemplate, in: context)
        } catch WorkoutSessionLifecycleError.openSessionAlreadyExists {
            didThrowOpenSessionError = true
        }

        #expect(didThrowOpenSessionError)
        #expect(try openSessionCount(in: context) == 1)
    }

    @Test func endingSessionAllowsNewSession() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let pushTemplate = try template(named: "Push A", in: context)
        let pullTemplate = try template(named: "Pull A", in: context)
        let endedAt = Date(timeIntervalSince1970: 3_600)

        let oldSession = try WorkoutSessionLifecycle.createSession(for: pushTemplate, in: context)
        try WorkoutSessionLifecycle.end(oldSession, in: context, endedAt: endedAt)
        let newSession = try WorkoutSessionLifecycle.createSession(for: pullTemplate, in: context)

        #expect(oldSession.endedAt == endedAt)
        #expect(newSession.templateNameSnapshot == "Pull A")
        #expect(try openSessionCount(in: context) == 1)
        #expect(try WorkoutSessionLifecycle.currentOpenSession(in: context)?.id == newSession.id)
    }

    @Test func discardDeletesSessionAndRelatedSets() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let set = WorkoutSet(
            session: session,
            exercise: exercise,
            exerciseNameSnapshot: exercise.name,
            exerciseOrderIndex: 0,
            setIndex: 1,
            weight: 30,
            reps: 8
        )

        context.insert(set)
        try context.save()
        try WorkoutSessionLifecycle.discard(session, in: context)

        #expect(try fetchSessions(in: context).isEmpty)
        #expect(try fetchSets(in: context).isEmpty)
    }

    @Test func exercisesFallbackToTemplateNameSnapshot() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        session.template = nil
        try context.save()

        let exerciseNames = try WorkoutSessionLifecycle.exercises(for: session, in: context).map(\.name)
        let expectedExerciseNames = try seedExerciseNames(for: "Push A")

        #expect(exerciseNames == expectedExerciseNames)
    }

    @Test func recordedSetCountsUseSnapshotsAndIgnoreOtherSessions() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let pushTemplate = try template(named: "Push A", in: context)
        let pullTemplate = try template(named: "Pull A", in: context)
        let benchPress = try exercise(named: "固定器械卧推", in: context)
        let inclinePress = try exercise(named: "上斜推胸机", in: context)
        let oldSession = try WorkoutSessionLifecycle.createSession(for: pullTemplate, in: context)

        context.insert(WorkoutSet(session: oldSession, exercise: benchPress, exerciseNameSnapshot: benchPress.name))
        try WorkoutSessionLifecycle.end(oldSession, in: context)

        let currentSession = try WorkoutSessionLifecycle.createSession(for: pushTemplate, in: context)
        context.insert(WorkoutSet(session: currentSession, exercise: benchPress, exerciseNameSnapshot: benchPress.name))
        context.insert(WorkoutSet(session: currentSession, exercise: benchPress, exerciseNameSnapshot: ""))
        context.insert(WorkoutSet(session: currentSession, exercise: inclinePress, exerciseNameSnapshot: inclinePress.name))
        try context.save()

        let counts = try WorkoutSessionLifecycle.recordedSetCountsByExerciseName(
            for: currentSession,
            in: context
        )

        #expect(counts["固定器械卧推"] == 2)
        #expect(counts["上斜推胸机"] == 1)
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

    private func fetchSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
    }

    private func fetchSets(in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(FetchDescriptor<WorkoutSet>())
    }

    private func templateCounts(_ templates: [Template]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: templates.map { ($0.name, $0.exercises.count) })
    }

    private func openSessionCount(in context: ModelContext) throws -> Int {
        try fetchSessions(in: context).filter { $0.endedAt == nil }.count
    }

    private func template(named name: String, in context: ModelContext) throws -> Template {
        guard let template = try fetchTemplates(in: context).first(where: { $0.name == name }) else {
            throw TestLookupError.missingTemplate(name)
        }

        return template
    }

    private func exercise(named name: String, in context: ModelContext) throws -> Exercise {
        guard let exercise = try fetchExercises(in: context).first(where: { $0.name == name }) else {
            throw TestLookupError.missingExercise(name)
        }

        return exercise
    }

    private func seedExerciseNames(for templateName: String) throws -> [String] {
        guard let template = SeedData.templateExerciseNames.first(where: { $0.name == templateName }) else {
            throw TestLookupError.missingTemplate(templateName)
        }

        return template.exerciseNames
    }
}

private enum TestLookupError: Error {
    case missingTemplate(String)
    case missingExercise(String)
    case missingTimeZone(String)
}
