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
        let orderedTemplates = templates.sorted { $0.sortIndex < $1.sortIndex }

        #expect(exercises.count == 19)
        #expect(templates.count == 6)
        #expect(orderedTemplates.map(\.name) == SeedData.templateExerciseNames.map(\.name))
        #expect(orderedTemplates.map(\.sortIndex) == Array(0..<6))
        #expect(templateCounts(templates) == [
            "Legs A": 5,
            "Legs B": 6,
            "Pull A": 5,
            "Pull B": 5,
            "Push A": 6,
            "Push B": 6,
        ])
        #expect(try templateExerciseCounts(in: context) == [
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
        #expect(try fetchTemplateExercises(in: context).count == 33)
    }

    @Test func seedDataDoesNotRestoreDeletedOrOverwriteEditedSeedData() throws {
        let context = try makeInMemoryContext()

        try SeedData.writeAndDedup(in: context)

        let benchPress = try exercise(named: "固定器械卧推", in: context)
        let deletedExercise = try exercise(named: "坐姿夹胸", in: context)
        let deletedTemplate = try template(named: "Pull B", in: context)

        benchPress.defaultRestSeconds = 333
        benchPress.isUnilateral = true
        context.delete(deletedExercise)
        context.delete(deletedTemplate)
        try context.save()

        try SeedData.writeAndDedup(in: context)

        let exerciseNames = try fetchExercises(in: context).map(\.name)
        let templateNames = try fetchTemplates(in: context).map(\.name)
        let editedBenchPress = try exercise(named: "固定器械卧推", in: context)

        #expect(exerciseNames.contains("坐姿夹胸") == false)
        #expect(templateNames.contains("Pull B") == false)
        #expect(editedBenchPress.defaultRestSeconds == 333)
        #expect(editedBenchPress.isUnilateral)
    }

    @Test func seedDataDoesNotResetTemplateExerciseOrder() throws {
        let context = try makeInMemoryContext()

        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let links = try templateExerciseLinks(for: template, in: context)

        links[0].orderIndex = 1
        links[1].orderIndex = 0
        try context.save()

        try SeedData.writeAndDedup(in: context)

        #expect(Array(try templateExerciseNames(for: template, in: context).prefix(2)) == [
            "上斜推胸机",
            "固定器械卧推",
        ])
    }

    @Test func seedDataBackfillsExistingTemplateSortIndexesAndNextAppendIndex() throws {
        let context = try makeInMemoryContext()
        let pushTemplate = Template(name: "Push A")
        let pullTemplate = Template(name: "Pull A")
        let customTemplate = Template(name: "Custom")

        context.insert(customTemplate)
        context.insert(pullTemplate)
        context.insert(pushTemplate)
        try context.save()

        try SeedData.writeAndDedup(in: context)

        let orderedTemplates = try fetchTemplates(in: context).sorted { $0.sortIndex < $1.sortIndex }

        #expect(orderedTemplates.map(\.name) == ["Push A", "Pull A", "Custom"])
        #expect(orderedTemplates.map(\.sortIndex) == [0, 1, 2])
        #expect(try SeedData.nextTemplateSortIndex(in: context) == 3)
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

    @Test func seedDataDedupsTemplatesWithoutDuplicatingTemplateExerciseLinks() throws {
        let context = try makeInMemoryContext()
        let exercises = SeedData.exercises()

        for exercise in exercises {
            context.insert(exercise)
        }

        let exerciseMap = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        let firstTemplate = Template(
            name: "Push A",
            exercises: ["固定器械卧推", "上斜推胸机"].compactMap { exerciseMap[$0] }
        )
        let duplicateTemplate = Template(
            name: "Push A",
            exercises: ["固定器械卧推", "上斜推胸机"].compactMap { exerciseMap[$0] }
        )

        context.insert(firstTemplate)
        context.insert(duplicateTemplate)

        for (index, exercise) in firstTemplate.exercises.enumerated() {
            context.insert(TemplateExercise(template: firstTemplate, exercise: exercise, orderIndex: index))
        }

        for (index, exercise) in duplicateTemplate.exercises.enumerated() {
            context.insert(TemplateExercise(template: duplicateTemplate, exercise: exercise, orderIndex: index))
        }

        try context.save()
        try SeedData.writeAndDedup(in: context)

        let templates = try fetchTemplates(in: context)
        let remainingTemplate = try template(named: "Push A", in: context)
        let remainingLinks = try templateExerciseLinks(for: remainingTemplate, in: context)

        #expect(templates.filter { $0.name == "Push A" }.count == 1)
        #expect(remainingLinks.map(\.orderIndex) == [0, 1])
        #expect(remainingLinks.compactMap { $0.exercise?.name } == ["固定器械卧推", "上斜推胸机"])
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
        #expect(try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context).map(\.name) == [
            "固定器械卧推",
            "上斜推胸机",
            "固定器械推肩",
            "坐姿夹胸",
            "哑铃侧平举",
            "坐姿肱三头伸展机",
        ])
        #expect(try fetchSessionExerciseSnapshots(in: context).count == 6)
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

    @Test func deleteCompletedSessionsDeletesSelectedSessionsAndSetsOnly() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let deletedSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let deletedSet = try WorkoutSetLogging.recordSet(
            sessionID: deletedSession.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            in: context
        )
        try WorkoutSessionLifecycle.end(deletedSession, in: context)

        let keptSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let keptSet = try WorkoutSetLogging.recordSet(
            sessionID: keptSession.id,
            exerciseName: exercise.name,
            weight: 32.5,
            reps: 7,
            rpe: nil,
            side: nil,
            in: context
        )
        try WorkoutSessionLifecycle.end(keptSession, in: context)

        try WorkoutSessionLifecycle.deleteCompletedSessions(sessionIDs: [deletedSession.id], in: context)

        let sessions = try fetchSessions(in: context)
        let sets = try fetchSets(in: context)

        #expect(sessions.map(\.id) == [keptSession.id])
        #expect(sets.map(\.id) == [keptSet.id])
        #expect(sets.contains { $0.id == deletedSet.id } == false)
    }

    @Test func deleteCompletedSessionsRejectsOpenSessionWithoutPartialDelete() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let endedSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        _ = try WorkoutSetLogging.recordSet(
            sessionID: endedSession.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            in: context
        )
        try WorkoutSessionLifecycle.end(endedSession, in: context)

        let openSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        _ = try WorkoutSetLogging.recordSet(
            sessionID: openSession.id,
            exerciseName: exercise.name,
            weight: 32.5,
            reps: 7,
            rpe: nil,
            side: nil,
            in: context
        )

        var didRejectOpenSession = false

        do {
            try WorkoutSessionLifecycle.deleteCompletedSessions(
                sessionIDs: [endedSession.id, openSession.id],
                in: context
            )
        } catch WorkoutSessionLifecycleError.cannotDeleteOpenSession {
            didRejectOpenSession = true
        }

        #expect(didRejectOpenSession)
        #expect(Set(try fetchSessions(in: context).map(\.id)) == Set([endedSession.id, openSession.id]))
        #expect(try fetchSets(in: context).count == 2)
    }

    @Test func exercisesFallbackToTemplateNameSnapshot() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        try deleteSnapshots(for: session, in: context)
        session.template = nil
        try context.save()

        let exerciseNames = try WorkoutSessionLifecycle.exercises(for: session, in: context).map(\.name)
        let expectedExerciseNames = try seedExerciseNames(for: "Push A")

        #expect(exerciseNames == expectedExerciseNames)
    }

    @Test func openSessionUsesExerciseSnapshotsAfterTemplateDeletion() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        context.delete(template)
        try context.save()

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

    @Test func openSessionExerciseSnapshotsDoNotFollowLaterTemplateEdits() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let benchPress = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let links = try templateExerciseLinks(for: template, in: context)

        links[0].orderIndex = 1
        links[1].orderIndex = 0
        benchPress.defaultRestSeconds = 333
        benchPress.isUnilateral = true
        try context.save()

        let descriptors = try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context)
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: "固定器械卧推",
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            in: context
        )

        #expect(Array(descriptors.map(\.name).prefix(2)) == ["固定器械卧推", "上斜推胸机"])
        #expect(descriptors[0].defaultRestSeconds == 120)
        #expect(descriptors[0].isUnilateral == false)
        #expect(set.exerciseOrderIndex == 0)
        #expect(set.side == nil)
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

    @Test func bilateralRecordingUsesTemplateOrderAndContinuousSetIndexes() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械推肩", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        let firstSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        let secondSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 32.5,
            reps: 7,
            rpe: 8,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 200),
            in: context
        )

        let savedSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseName: exercise.name,
            side: nil,
            in: context
        )

        #expect(firstSet.exerciseOrderIndex == 2)
        #expect(secondSet.exerciseOrderIndex == 2)
        #expect(savedSets.map(\.setIndex) == [1, 2])
        #expect(savedSets.map(\.side) == [nil, nil])
        #expect(savedSets.map(\.exerciseNameSnapshot) == [exercise.name, exercise.name])
    }

    @Test func exerciseOrderIndexFallsBackToTemplateNameSnapshot() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械推肩", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        try deleteSnapshots(for: session, in: context)
        session.template = nil
        try context.save()

        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            in: context
        )

        #expect(set.exerciseOrderIndex == 2)
    }

    @Test func unilateralHalfSetRecoveryAndSameSidePrefill() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Legs A", in: context)
        let exercise = try exercise(named: "跪姿单腿腿弯举", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseName: exercise.name,
            in: context
        ) == .left)

        let leftSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 24.9,
            reps: 12,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )

        #expect(leftSet.setIndex == 1)
        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseName: exercise.name,
            in: context
        ) == .right)
        #expect(try WorkoutSetLogging.lastValues(
            exerciseName: exercise.name,
            side: .left,
            in: context
        ) == WorkoutSetValues(weight: 24.9, reps: 12))
        #expect(try WorkoutSetLogging.lastValues(
            exerciseName: exercise.name,
            side: .right,
            in: context
        ) == nil)

        let rightSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 22.5,
            reps: 10,
            rpe: 9,
            side: .right,
            completedAt: Date(timeIntervalSince1970: 200),
            in: context
        )

        #expect(rightSet.setIndex == 1)
        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseName: exercise.name,
            in: context
        ) == .left)
        #expect(try WorkoutSetLogging.lastValues(
            exerciseName: exercise.name,
            side: .right,
            in: context
        ) == WorkoutSetValues(weight: 22.5, reps: 10))
    }

    @Test func unilateralRecoveryFallsBackToLeftWhenRightSideHasExtraSet() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Legs A", in: context)
        let exercise = try exercise(named: "跪姿单腿腿弯举", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 22.5,
            reps: 10,
            rpe: nil,
            side: .right,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )

        #expect(try WorkoutSetLogging.sideCounts(
            sessionID: session.id,
            exerciseName: exercise.name,
            in: context
        ) == WorkoutSideCounts(left: 0, right: 1))
        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseName: exercise.name,
            in: context
        ) == .left)
    }

    @Test func deletingCompletedRightSideInfersRightAsPendingSide() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Legs A", in: context)
        let exercise = try exercise(named: "跪姿单腿腿弯举", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 20,
            reps: 12,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        let deletedRightSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 20,
            reps: 11,
            rpe: nil,
            side: .right,
            completedAt: Date(timeIntervalSince1970: 110),
            in: context
        )

        try WorkoutSetLogging.deleteAndRenumber(deletedRightSet, in: context)

        #expect(try WorkoutSetLogging.sideCounts(
            sessionID: session.id,
            exerciseName: exercise.name,
            in: context
        ) == WorkoutSideCounts(left: 1, right: 0))
        #expect(try WorkoutSetLogging.inferredNextSide(
            sessionID: session.id,
            exerciseName: exercise.name,
            in: context
        ) == .right)
    }

    @Test func deletingBilateralSetRenumbersRemainingSetsByCompletedAt() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        let deletedSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 32.5,
            reps: 7,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 200),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 35,
            reps: 6,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 300),
            in: context
        )

        try WorkoutSetLogging.deleteAndRenumber(deletedSet, in: context)

        let remainingSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseName: exercise.name,
            side: nil,
            in: context
        )

        #expect(remainingSets.map(\.weight) == [30, 35])
        #expect(remainingSets.map(\.setIndex) == [1, 2])
    }

    @Test func deletingUnilateralSetRenumbersOnlyThatSide() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Legs A", in: context)
        let exercise = try exercise(named: "跪姿单腿腿弯举", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 20,
            reps: 12,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 21,
            reps: 12,
            rpe: nil,
            side: .right,
            completedAt: Date(timeIntervalSince1970: 110),
            in: context
        )
        let deletedLeftSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 22,
            reps: 10,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 200),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 23,
            reps: 10,
            rpe: nil,
            side: .right,
            completedAt: Date(timeIntervalSince1970: 210),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 24,
            reps: 8,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 300),
            in: context
        )

        try WorkoutSetLogging.deleteAndRenumber(deletedLeftSet, in: context)

        let leftSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseName: exercise.name,
            side: .left,
            in: context
        )
        let rightSets = try WorkoutSetLogging.sets(
            sessionID: session.id,
            exerciseName: exercise.name,
            side: .right,
            in: context
        )

        #expect(leftSets.map(\.weight) == [20, 24])
        #expect(leftSets.map(\.setIndex) == [1, 2])
        #expect(rightSets.map(\.weight) == [21, 23])
        #expect(rightSets.map(\.setIndex) == [1, 2])
    }

    @Test func recordingSetInEndedSessionThrowsAndDoesNotInsertSet() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        try WorkoutSessionLifecycle.end(session, in: context)

        var didThrowEndedSession = false

        do {
            _ = try WorkoutSetLogging.recordSet(
                sessionID: session.id,
                exerciseName: exercise.name,
                weight: 30,
                reps: 8,
                rpe: nil,
                side: nil,
                in: context
            )
        } catch WorkoutSetLoggingError.sessionAlreadyEnded {
            didThrowEndedSession = true
        }

        #expect(didThrowEndedSession)
        #expect(try fetchSets(in: context).isEmpty)
    }

    @Test func invalidSetInputDoesNotInsertSets() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        for invalidWeight in [-1, Double.nan] {
            var didThrowInvalidWeight = false

            do {
                _ = try WorkoutSetLogging.recordSet(
                    sessionID: session.id,
                    exerciseName: exercise.name,
                    weight: invalidWeight,
                    reps: 8,
                    rpe: nil,
                    side: nil,
                    in: context
                )
            } catch WorkoutSetLoggingError.invalidWeight {
                didThrowInvalidWeight = true
            }

            #expect(didThrowInvalidWeight)
        }

        var didThrowInvalidReps = false

        do {
            _ = try WorkoutSetLogging.recordSet(
                sessionID: session.id,
                exerciseName: exercise.name,
                weight: 30,
                reps: 0,
                rpe: nil,
                side: nil,
                in: context
            )
        } catch WorkoutSetLoggingError.invalidReps {
            didThrowInvalidReps = true
        }

        #expect(didThrowInvalidReps)
        #expect(try fetchSets(in: context).isEmpty)
    }

    @Test func rpeValidationAllowsOnlyIntegerSixThroughTen() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        #expect(WorkoutSetLogging.allowedRPEValues == [6, 7, 8, 9, 10])

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: 6,
            side: nil,
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: 10,
            side: nil,
            in: context
        )

        for invalidRPE in [5, 11, 75] {
            var didThrowInvalidRPE = false

            do {
                _ = try WorkoutSetLogging.recordSet(
                    sessionID: session.id,
                    exerciseName: exercise.name,
                    weight: 30,
                    reps: 8,
                    rpe: invalidRPE,
                    side: nil,
                    in: context
                )
            } catch WorkoutSetLoggingError.invalidRPE(let value) {
                didThrowInvalidRPE = value == invalidRPE
            }

            #expect(didThrowInvalidRPE)
        }
    }

    @Test func sideValidationMatchesExerciseKind() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Legs A", in: context)
        let bilateralExercise = try exercise(named: "腿举机", in: context)
        let unilateralExercise = try exercise(named: "跪姿单腿腿弯举", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        var didThrowMissingSide = false

        do {
            _ = try WorkoutSetLogging.recordSet(
                sessionID: session.id,
                exerciseName: unilateralExercise.name,
                weight: 20,
                reps: 12,
                rpe: nil,
                side: nil,
                in: context
            )
        } catch WorkoutSetLoggingError.missingSideForUnilateralExercise {
            didThrowMissingSide = true
        }

        var didThrowSideNotAllowed = false

        do {
            _ = try WorkoutSetLogging.recordSet(
                sessionID: session.id,
                exerciseName: bilateralExercise.name,
                weight: 100,
                reps: 10,
                rpe: nil,
                side: .left,
                in: context
            )
        } catch WorkoutSetLoggingError.sideNotAllowedForBilateralExercise {
            didThrowSideNotAllowed = true
        }

        #expect(didThrowMissingSide)
        #expect(didThrowSideNotAllowed)
        #expect(try fetchSets(in: context).isEmpty)
    }

    @Test func lastValuesUseSnapshotsWhenExerciseRelationshipIsMissing() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 32.5,
            reps: 7,
            rpe: nil,
            side: nil,
            in: context
        )

        set.exercise = nil
        try context.save()

        #expect(try WorkoutSetLogging.lastValues(
            exerciseName: exercise.name,
            side: nil,
            in: context
        ) == WorkoutSetValues(weight: 32.5, reps: 7))
    }

    @Test func setIndexesAndDeletionAreIsolatedAcrossSessions() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let oldSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let oldSet = try WorkoutSetLogging.recordSet(
            sessionID: oldSession.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )

        try WorkoutSessionLifecycle.end(oldSession, in: context)

        let currentSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let currentSet = try WorkoutSetLogging.recordSet(
            sessionID: currentSession.id,
            exerciseName: exercise.name,
            weight: 32.5,
            reps: 7,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 200),
            in: context
        )

        #expect(oldSet.setIndex == 1)
        #expect(currentSet.setIndex == 1)

        try WorkoutSetLogging.deleteAndRenumber(oldSet, in: context)

        let currentSets = try WorkoutSetLogging.sets(
            sessionID: currentSession.id,
            exerciseName: exercise.name,
            side: nil,
            in: context
        )

        #expect(currentSets.map(\.weight) == [32.5])
        #expect(currentSets.map(\.setIndex) == [1])
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

    private func fetchTemplates(in context: ModelContext) throws -> [Template] {
        try context.fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.name)]))
    }

    private func fetchTemplateExercises(in context: ModelContext) throws -> [TemplateExercise] {
        try context.fetch(FetchDescriptor<TemplateExercise>())
    }

    private func fetchSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
    }

    private func fetchSessionExerciseSnapshots(in context: ModelContext) throws -> [WorkoutSessionExerciseSnapshot] {
        try context.fetch(FetchDescriptor<WorkoutSessionExerciseSnapshot>())
    }

    private func fetchSets(in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(FetchDescriptor<WorkoutSet>())
    }

    private func templateCounts(_ templates: [Template]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: templates.map { ($0.name, $0.exercises.count) })
    }

    private func templateExerciseCounts(in context: ModelContext) throws -> [String: Int] {
        let links = try fetchTemplateExercises(in: context)
        var counts: [String: Int] = [:]

        for link in links {
            guard let templateName = link.template?.name, link.exercise != nil else {
                continue
            }

            counts[templateName, default: 0] += 1
        }

        return counts
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

    private func templateExerciseNames(for template: Template, in context: ModelContext) throws -> [String] {
        try templateExerciseLinks(for: template, in: context).compactMap { $0.exercise?.name }
    }

    private func deleteSnapshots(for session: WorkoutSession, in context: ModelContext) throws {
        for snapshot in try fetchSessionExerciseSnapshots(in: context) where snapshot.session?.id == session.id {
            context.delete(snapshot)
        }
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
