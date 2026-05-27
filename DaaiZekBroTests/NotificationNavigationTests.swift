import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct NotificationNavigationTests {
    @Test func restNotificationPayloadRoundTripsThroughUserInfo() throws {
        let sessionID = UUID()
        let payload = RestNotificationPayload(sessionID: sessionID, exerciseName: "固定器械卧推")

        #expect(RestNotificationPayload(userInfo: payload.userInfo) == payload)
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
        let payload = RestNotificationPayload(sessionID: session.id, exerciseName: "固定器械卧推")

        let route = try NotificationNavigationResolver.route(for: payload, in: context)

        #expect(route == [
            .currentWorkout(sessionID: session.id),
            .exerciseLogging(sessionID: session.id, exerciseName: "固定器械卧推"),
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
        let payload = RestNotificationPayload(sessionID: session.id, exerciseName: "固定器械卧推")
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
            .exerciseLogging(sessionID: session.id, exerciseName: "固定器械卧推"),
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

    private func template(named name: String, in context: ModelContext) throws -> Template {
        let templates = try context.fetch(FetchDescriptor<Template>())

        guard let template = templates.first(where: { $0.name == name }) else {
            throw NotificationNavigationTestError.missingTemplate(name)
        }

        return template
    }
}

private enum NotificationNavigationTestError: Error {
    case missingTemplate(String)
}
