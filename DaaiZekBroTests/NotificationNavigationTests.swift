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

    @Test func notificationForMissingSessionRoutesHome() throws {
        let context = try makeInMemoryContext()
        let payload = RestNotificationPayload(sessionID: UUID(), exerciseName: "固定器械卧推")

        #expect(try NotificationNavigationResolver.route(for: payload, in: context) == [])
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
