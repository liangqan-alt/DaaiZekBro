import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct NotificationNavigationTests {
    @Test func restNotificationPayloadRoundTripsThroughUserInfo() throws {
        let sessionID = UUID()
        let payload = RestNotificationPayload(
            sessionID: sessionID,
            exerciseName: "固定器械卧推",
            exerciseOrderIndex: 2
        )
        let oldPayload = RestNotificationPayload(sessionID: sessionID, exerciseName: "固定器械卧推")

        #expect(RestNotificationPayload(userInfo: payload.userInfo) == payload)
        #expect(payload.userInfo[RestNotificationPayload.exerciseOrderIndexKey] as? Int == 2)
        #expect(oldPayload.exerciseOrderIndex == nil)
        #expect(oldPayload.userInfo[RestNotificationPayload.exerciseOrderIndexKey] == nil)
        #expect(RestNotificationPayload(userInfo: oldPayload.userInfo) == oldPayload)
        #expect(RestNotificationPayload(userInfo: [
            RestNotificationPayload.sessionIDKey: "not-a-uuid",
            RestNotificationPayload.exerciseNameKey: "固定器械卧推",
        ]) == nil)
    }

    @Test func notificationForOpenSessionRoutesToExerciseLogging() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let payload = RestNotificationPayload(
            sessionID: session.id,
            exerciseName: "固定器械卧推",
            exerciseOrderIndex: 0
        )

        let route = try NotificationNavigationResolver.route(for: payload, in: context)

        #expect(route == [
            .currentWorkout(sessionID: session.id),
            .exerciseLogging(sessionID: session.id, exerciseOrderIndex: 0, exerciseName: "固定器械卧推"),
        ])
    }

    @Test func notificationRoutesExactlyByExerciseOrderIndexWhenNamesAreDuplicated() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            exercises: [
                Exercise(name: "Cable Row"),
                Exercise(name: "Cable Row"),
            ],
            in: context
        )
        let payload = RestNotificationPayload(
            sessionID: session.id,
            exerciseName: "Cable Row",
            exerciseOrderIndex: 1
        )

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [
            .currentWorkout(sessionID: session.id),
            .exerciseLogging(sessionID: session.id, exerciseOrderIndex: 1, exerciseName: "Cable Row"),
        ])
    }

    @Test func notificationWithMismatchedOrderIndexRoutesOnlyToCurrentWorkout() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let payload = RestNotificationPayload(
            sessionID: session.id,
            exerciseName: "固定器械卧推",
            exerciseOrderIndex: 99
        )

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [
            .currentWorkout(sessionID: session.id),
        ])
    }

    @Test func notificationWithoutOrderIndexFallsBackToExerciseNameForOldPayloads() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let payload = RestNotificationPayload(sessionID: session.id, exerciseName: "固定器械卧推")

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [
            .currentWorkout(sessionID: session.id),
            .exerciseLogging(sessionID: session.id, exerciseOrderIndex: 0, exerciseName: "固定器械卧推"),
        ])
    }

    @Test func oldNameOnlyNotificationForDuplicateNamesRoutesOnlyToCurrentWorkout() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            exercises: [
                Exercise(name: "Cable Row"),
                Exercise(name: "Cable Row"),
            ],
            in: context
        )
        let payload = RestNotificationPayload(sessionID: session.id, exerciseName: "Cable Row")

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [
            .currentWorkout(sessionID: session.id),
        ])
    }

    @Test func indexedNotificationRouteDoesNotDriftAfterTemplateAndExerciseEdits() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let benchPress = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let links = try templateExerciseLinks(for: template, in: context)
        let payload = RestNotificationPayload(
            sessionID: session.id,
            exerciseName: "固定器械卧推",
            exerciseOrderIndex: 0
        )

        links[0].orderIndex = 5
        links[1].orderIndex = 0
        benchPress.name = "固定器械卧推 - Edited"
        try context.save()

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [
            .currentWorkout(sessionID: session.id),
            .exerciseLogging(sessionID: session.id, exerciseOrderIndex: 0, exerciseName: "固定器械卧推"),
        ])
    }

    @Test func notificationForEndedSessionRoutesHome() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        try WorkoutSessionLifecycle.end(session, in: context)
        let payload = RestNotificationPayload(sessionID: session.id, exerciseName: "固定器械卧推")

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [])
    }

    @Test func notificationForDiscardedSessionRoutesHome() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let payload = RestNotificationPayload(
            sessionID: session.id,
            exerciseName: "固定器械卧推",
            exerciseOrderIndex: 0
        )
        try WorkoutSessionLifecycle.discard(session, in: context)

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [])
    }

    @Test func notificationForExerciseOutsideSessionRoutesToCurrentWorkout() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let payload = RestNotificationPayload(sessionID: session.id, exerciseName: "跪姿单腿腿弯举")

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [
            .currentWorkout(sessionID: session.id),
        ])
    }

    @Test func notificationRoutesUsingSessionSnapshotsAfterTemplateDeletion() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)
        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        let payload = RestNotificationPayload(sessionID: session.id, exerciseName: "固定器械卧推")

        context.delete(template)
        try context.save()

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [
            .currentWorkout(sessionID: session.id),
            .exerciseLogging(sessionID: session.id, exerciseOrderIndex: 0, exerciseName: "固定器械卧推"),
        ])
    }

    @Test func notificationForMissingSessionRoutesHome() throws {
        let context = try makeInMemoryContext()
        let payload = RestNotificationPayload(sessionID: UUID(), exerciseName: "固定器械卧推")

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [])
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

        return ModelContext(container)
    }

    private func makeSession(exercises: [Exercise], in context: ModelContext) throws -> WorkoutSession {
        let template = Template(name: "Notification Test")

        context.insert(template)

        for (index, exercise) in exercises.enumerated() {
            context.insert(exercise)
            context.insert(TemplateExercise(template: template, exercise: exercise, orderIndex: index))
        }

        try context.save()

        return try WorkoutSessionLifecycle.createSession(for: template, in: context)
    }

    private func template(named name: String, in context: ModelContext) throws -> Template {
        let templates = try context.fetch(FetchDescriptor<Template>())

        guard let template = templates.first(where: { $0.name == name }) else {
            throw NotificationNavigationTestError.missingTemplate(name)
        }

        return template
    }

    private func exercise(named name: String, in context: ModelContext) throws -> Exercise {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        guard let exercise = exercises.first(where: { $0.name == name }) else {
            throw NotificationNavigationTestError.missingExercise(name)
        }

        return exercise
    }

    private func templateExerciseLinks(for template: Template, in context: ModelContext) throws -> [TemplateExercise] {
        try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { $0.template === template }
            .sortedByTemplateExerciseOrder()
    }
}

private enum NotificationNavigationTestError: Error {
    case missingExercise(String)
    case missingTemplate(String)
}
