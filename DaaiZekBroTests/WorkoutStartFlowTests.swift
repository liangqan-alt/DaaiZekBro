import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct WorkoutStartFlowTests {
    @Test func startingPlanWorkoutCreatesSameSessionMetadataAsManualStart() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let template = Template(name: "Push A", stableID: "template-push-a")
        context.insert(template)
        try context.save()

        let result = try WorkoutStartFlow.startOrConflict(
            for: template,
            in: context,
            startedAt: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        guard case .started(let session) = result else {
            Issue.record("Expected a started session")
            return
        }

        #expect(session.template?.persistentModelID == template.persistentModelID)
        #expect(session.templateNameSnapshot == "Push A")
        #expect(session.templateStableIDSnapshot == "template-push-a")
        #expect(session.timezoneIdentifier == "Asia/Shanghai")
        #expect(session.endedAt == nil)
        #expect(try openSessionCount(in: context) == 1)
    }

    @Test func startingPlanWorkoutWithOpenSessionReturnsConflictAndCreatesNoSession() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = Template(name: "Push A", stableID: "template-push-a")
        let pull = Template(name: "Pull A", stableID: "template-pull-a")
        context.insert(push)
        context.insert(pull)
        try context.save()
        let openSession = try WorkoutSessionLifecycle.createSession(
            for: push,
            in: context,
            startedAt: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        let result = try WorkoutStartFlow.startOrConflict(
            for: pull,
            in: context,
            startedAt: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        guard case .conflict(let session) = result else {
            Issue.record("Expected an open-session conflict")
            return
        }

        #expect(session.id == openSession.id)
        #expect(try openSessionCount(in: context) == 1)
        #expect(try fetchSessions(in: context).first?.templateNameSnapshot == "Push A")
    }

    @Test func resolvingConflictByEndingCreatesNewSessionAndCancelsNotificationOnSuccess() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = Template(name: "Push A", stableID: "template-push-a")
        let pull = Template(name: "Pull A", stableID: "template-pull-a")
        let resolvedAt = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let notificationCanceller = SpyRestNotificationCanceller()
        context.insert(push)
        context.insert(pull)
        try context.save()
        let oldSession = try WorkoutSessionLifecycle.createSession(
            for: push,
            in: context,
            startedAt: try date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        let newSession = try WorkoutConflictResolution.resolve(
            choice: .endCurrentAndCreate,
            for: pull,
            in: context,
            resolvedAt: resolvedAt,
            timeZone: timeZone,
            notificationCanceller: notificationCanceller.canceller
        )

        #expect(oldSession.endedAt == resolvedAt)
        #expect(newSession.templateNameSnapshot == "Pull A")
        #expect(newSession.startedAt == resolvedAt)
        #expect(try openSessionCount(in: context) == 1)
        #expect(try WorkoutSessionLifecycle.currentOpenSession(in: context)?.id == newSession.id)
        #expect(notificationCanceller.cancelCount == 1)
    }

    @Test func resolvingConflictByDiscardingCreatesNewSessionAndCancelsNotificationOnSuccess() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = Template(name: "Push A", stableID: "template-push-a")
        let pull = Template(name: "Pull A", stableID: "template-pull-a")
        let exercise = Exercise(name: "Bench Press")
        let resolvedAt = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let notificationCanceller = SpyRestNotificationCanceller()
        context.insert(push)
        context.insert(pull)
        context.insert(exercise)
        try context.save()
        let oldSession = try WorkoutSessionLifecycle.createSession(
            for: push,
            in: context,
            startedAt: try date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        context.insert(
            WorkoutSet(
                session: oldSession,
                exercise: exercise,
                exerciseNameSnapshot: exercise.name,
                exerciseOrderIndex: 0,
                setIndex: 1,
                weight: 30,
                reps: 8
            )
        )
        try context.save()

        let newSession = try WorkoutConflictResolution.resolve(
            choice: .discardCurrentAndCreate,
            for: pull,
            in: context,
            resolvedAt: resolvedAt,
            timeZone: timeZone,
            notificationCanceller: notificationCanceller.canceller
        )

        #expect(try fetchSessions(in: context).map(\.id).contains(oldSession.id) == false)
        #expect(try fetchSets(in: context).isEmpty)
        #expect(newSession.templateNameSnapshot == "Pull A")
        #expect(newSession.startedAt == resolvedAt)
        #expect(try openSessionCount(in: context) == 1)
        #expect(try WorkoutSessionLifecycle.currentOpenSession(in: context)?.id == newSession.id)
        #expect(notificationCanceller.cancelCount == 1)
    }

    @Test func endingConflictDoesNotCancelNotificationWhenNewSessionCreationFails() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = Template(name: "Push A", stableID: "template-push-a")
        let pull = Template(name: "Pull A", stableID: "template-pull-a")
        let resolvedAt = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let notificationCanceller = SpyRestNotificationCanceller()
        context.insert(push)
        context.insert(pull)
        try context.save()
        let oldSession = try WorkoutSessionLifecycle.createSession(
            for: push,
            in: context,
            startedAt: try date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        do {
            _ = try WorkoutConflictResolution.resolve(
                choice: .endCurrentAndCreate,
                for: pull,
                in: context,
                resolvedAt: resolvedAt,
                timeZone: timeZone,
                notificationCanceller: notificationCanceller.canceller,
                dependencies: dependenciesThrowingOnCreate()
            )
            Issue.record("Expected create failure")
        } catch WorkoutStartFlowTestError.createFailed {
            #expect(oldSession.endedAt == resolvedAt)
            #expect(try fetchSessions(in: context).count == 1)
            #expect(try openSessionCount(in: context) == 0)
            #expect(notificationCanceller.cancelCount == 0)
        }
    }

    @Test func retryAfterEndingConflictCreateFailureCancelsNotificationWhenCreateSucceeds() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = Template(name: "Push A", stableID: "template-push-a")
        let pull = Template(name: "Pull A", stableID: "template-pull-a")
        let failedAt = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let retriedAt = try date(2026, 1, 1, 12, 1, 0, timeZone: timeZone)
        let notificationCanceller = SpyRestNotificationCanceller()
        context.insert(push)
        context.insert(pull)
        try context.save()
        let oldSession = try WorkoutSessionLifecycle.createSession(
            for: push,
            in: context,
            startedAt: try date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        do {
            _ = try WorkoutConflictResolution.resolve(
                choice: .endCurrentAndCreate,
                for: pull,
                in: context,
                resolvedAt: failedAt,
                timeZone: timeZone,
                notificationCanceller: notificationCanceller.canceller,
                dependencies: dependenciesThrowingOnCreate()
            )
            Issue.record("Expected create failure")
        } catch WorkoutStartFlowTestError.createFailed {
            #expect(oldSession.endedAt == failedAt)
            #expect(try openSessionCount(in: context) == 0)
            #expect(notificationCanceller.cancelCount == 0)
        }

        let newSession = try WorkoutConflictResolution.resolve(
            choice: .endCurrentAndCreate,
            for: pull,
            in: context,
            resolvedAt: retriedAt,
            timeZone: timeZone,
            notificationCanceller: notificationCanceller.canceller
        )

        #expect(oldSession.endedAt == failedAt)
        #expect(newSession.templateNameSnapshot == "Pull A")
        #expect(newSession.startedAt == retriedAt)
        #expect(try openSessionCount(in: context) == 1)
        #expect(try WorkoutSessionLifecycle.currentOpenSession(in: context)?.id == newSession.id)
        #expect(notificationCanceller.cancelCount == 1)
    }

    @Test func discardingConflictDoesNotCancelNotificationWhenNewSessionCreationFails() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = Template(name: "Push A", stableID: "template-push-a")
        let pull = Template(name: "Pull A", stableID: "template-pull-a")
        let exercise = Exercise(name: "Bench Press")
        let resolvedAt = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let notificationCanceller = SpyRestNotificationCanceller()
        context.insert(push)
        context.insert(pull)
        context.insert(exercise)
        try context.save()
        let oldSession = try WorkoutSessionLifecycle.createSession(
            for: push,
            in: context,
            startedAt: try date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        context.insert(
            WorkoutSet(
                session: oldSession,
                exercise: exercise,
                exerciseNameSnapshot: exercise.name,
                exerciseOrderIndex: 0,
                setIndex: 1,
                weight: 30,
                reps: 8
            )
        )
        try context.save()

        do {
            _ = try WorkoutConflictResolution.resolve(
                choice: .discardCurrentAndCreate,
                for: pull,
                in: context,
                resolvedAt: resolvedAt,
                timeZone: timeZone,
                notificationCanceller: notificationCanceller.canceller,
                dependencies: dependenciesThrowingOnCreate()
            )
            Issue.record("Expected create failure")
        } catch WorkoutStartFlowTestError.createFailed {
            #expect(try fetchSessions(in: context).isEmpty)
            #expect(try fetchSets(in: context).isEmpty)
            #expect(notificationCanceller.cancelCount == 0)
        }
    }

    @Test func retryAfterDiscardingConflictCreateFailureCancelsNotificationWhenCreateSucceeds() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = Template(name: "Push A", stableID: "template-push-a")
        let pull = Template(name: "Pull A", stableID: "template-pull-a")
        let exercise = Exercise(name: "Bench Press")
        let failedAt = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let retriedAt = try date(2026, 1, 1, 12, 1, 0, timeZone: timeZone)
        let notificationCanceller = SpyRestNotificationCanceller()
        context.insert(push)
        context.insert(pull)
        context.insert(exercise)
        try context.save()
        let oldSession = try WorkoutSessionLifecycle.createSession(
            for: push,
            in: context,
            startedAt: try date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        context.insert(
            WorkoutSet(
                session: oldSession,
                exercise: exercise,
                exerciseNameSnapshot: exercise.name,
                exerciseOrderIndex: 0,
                setIndex: 1,
                weight: 30,
                reps: 8
            )
        )
        try context.save()

        do {
            _ = try WorkoutConflictResolution.resolve(
                choice: .discardCurrentAndCreate,
                for: pull,
                in: context,
                resolvedAt: failedAt,
                timeZone: timeZone,
                notificationCanceller: notificationCanceller.canceller,
                dependencies: dependenciesThrowingOnCreate()
            )
            Issue.record("Expected create failure")
        } catch WorkoutStartFlowTestError.createFailed {
            #expect(try fetchSessions(in: context).isEmpty)
            #expect(try fetchSets(in: context).isEmpty)
            #expect(notificationCanceller.cancelCount == 0)
        }

        let newSession = try WorkoutConflictResolution.resolve(
            choice: .discardCurrentAndCreate,
            for: pull,
            in: context,
            resolvedAt: retriedAt,
            timeZone: timeZone,
            notificationCanceller: notificationCanceller.canceller
        )

        #expect(try fetchSessions(in: context).map(\.id).contains(oldSession.id) == false)
        #expect(try fetchSets(in: context).isEmpty)
        #expect(newSession.templateNameSnapshot == "Pull A")
        #expect(newSession.startedAt == retriedAt)
        #expect(try openSessionCount(in: context) == 1)
        #expect(try WorkoutSessionLifecycle.currentOpenSession(in: context)?.id == newSession.id)
        #expect(notificationCanceller.cancelCount == 1)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

        return ModelContext(container)
    }

    private func fetchSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
    }

    private func fetchSets(in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(FetchDescriptor<WorkoutSet>())
    }

    private func openSessionCount(in context: ModelContext) throws -> Int {
        try fetchSessions(in: context).filter { $0.endedAt == nil }.count
    }

    private func dependenciesThrowingOnCreate() -> WorkoutConflictResolution.Dependencies {
        WorkoutConflictResolution.Dependencies(
            currentOpenSession: { context in
                try WorkoutSessionLifecycle.currentOpenSession(in: context)
            },
            endSession: { session, context, endedAt in
                try WorkoutSessionLifecycle.end(session, in: context, endedAt: endedAt)
            },
            discardSession: { session, context in
                try WorkoutSessionLifecycle.discard(session, in: context)
            },
            createSession: { _, _, _, _ in
                throw WorkoutStartFlowTestError.createFailed
            }
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        guard let date = components.date else {
            throw WorkoutStartFlowTestError.invalidDate
        }

        return date
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw WorkoutStartFlowTestError.missingTimeZone(identifier)
        }

        return timeZone
    }
}

private enum WorkoutStartFlowTestError: Error {
    case invalidDate
    case missingTimeZone(String)
    case createFailed
}

@MainActor
private final class SpyRestNotificationCanceller {
    private(set) var cancelCount = 0

    var canceller: WorkoutConflictResolution.NotificationCanceller {
        WorkoutConflictResolution.NotificationCanceller {
            self.cancelCount += 1
        }
    }
}
