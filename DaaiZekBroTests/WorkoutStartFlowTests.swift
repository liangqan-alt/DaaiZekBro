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

    private func fetchSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
    }

    private func openSessionCount(in context: ModelContext) throws -> Int {
        try fetchSessions(in: context).filter { $0.endedAt == nil }.count
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
}
