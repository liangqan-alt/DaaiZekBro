#if DEBUG
import Foundation
import SwiftData

@MainActor
enum UITestFixtures {
    static func write(
        named name: String,
        now: Date,
        in context: ModelContext
    ) throws {
        guard try isStoreEmpty(in: context) else {
            return
        }

        try SeedData.writeAndDedup(in: context)

        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let push = try template(named: "Push A", in: context)
        let pull = try template(named: "Pull A", in: context)
        let today = startOfDay(for: now, timeZone: timeZone)

        switch name {
        case "training-day-override-ready":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
        case "training-day-override-completed":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
            try createEndedSession(for: push, startedAt: now, timeZone: timeZone, in: context)
        case "today-plan-no-cycle":
            return
        case "today-plan-ready":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
            try createEndedSession(
                for: push,
                startedAt: date(2025, 12, 30, 12, 0, 0, timeZone: timeZone),
                timeZone: timeZone,
                in: context
            )
        case "today-plan-completed":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
            try createEndedSession(for: push, startedAt: now, timeZone: timeZone, in: context)
        case "today-plan-offplan":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
            try createEndedSession(for: pull, startedAt: now, timeZone: timeZone, in: context)
        case "today-plan-rest":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .rest),
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
        case "today-plan-rest-workout":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .rest),
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
            try createEndedSession(for: pull, startedAt: now, timeZone: timeZone, in: context)
        case "today-plan-invalid":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
            try TemplateLibrary.delete(push, in: context)
        case "today-plan-open-session":
            try createCycle(startDate: today, timeZone: timeZone, slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: push),
            ], in: context)
            _ = try WorkoutSessionLifecycle.createSession(
                for: push,
                in: context,
                startedAt: now,
                timeZone: timeZone
            )
        case "templates-empty":
            try deleteTemplates(except: [], in: context)
        case "templates-single":
            try deleteTemplates(except: ["Push A"], in: context)
        case "template-open-session-no-cycle":
            _ = try WorkoutSessionLifecycle.createSession(
                for: push,
                in: context,
                startedAt: now,
                timeZone: timeZone
            )
        case "recent-training-mixed":
            try createEndedSession(
                for: pull,
                startedAt: date(2026, 1, 1, 10, 0, 0, timeZone: timeZone),
                timeZone: timeZone,
                in: context
            )
            try createEndedSessionWithSet(
                for: push,
                startedAt: date(2025, 12, 31, 8, 0, 0, timeZone: timeZone),
                endedAt: date(2025, 12, 31, 9, 2, 0, timeZone: timeZone),
                timeZone: timeZone,
                in: context
            )
            try createEndedSessionWithSet(
                for: pull,
                startedAt: date(2025, 12, 30, 18, 0, 0, timeZone: timeZone),
                endedAt: date(2025, 12, 30, 18, 54, 0, timeZone: timeZone),
                timeZone: timeZone,
                in: context
            )
            try createEndedSessionWithSet(
                for: try template(named: "Legs A", in: context),
                startedAt: date(2025, 12, 29, 8, 0, 0, timeZone: timeZone),
                endedAt: date(2025, 12, 29, 8, 48, 0, timeZone: timeZone),
                timeZone: timeZone,
                in: context
            )
            try createEndedSessionWithSet(
                for: push,
                startedAt: date(2025, 12, 28, 8, 0, 0, timeZone: timeZone),
                endedAt: date(2025, 12, 28, 8, 45, 0, timeZone: timeZone),
                timeZone: timeZone,
                in: context
            )
            try createOpenSessionWithSet(
                for: pull,
                startedAt: date(2026, 1, 1, 11, 0, 0, timeZone: timeZone),
                timeZone: timeZone,
                in: context
            )
        default:
            throw UITestFixtureError.unknownFixture(name)
        }
    }

    private static func isStoreEmpty(in context: ModelContext) throws -> Bool {
        let templates = try context.fetch(FetchDescriptor<Template>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let cycles = try context.fetch(FetchDescriptor<TrainingCycle>())

        return templates.isEmpty && sessions.isEmpty && cycles.isEmpty
    }

    private static func createCycle(
        startDate: Date,
        timeZone: TimeZone,
        slots: [TrainingScheduleSlotDraft],
        in context: ModelContext
    ) throws {
        _ = try TrainingScheduleEngine.createCycle(
            startDate: startDate,
            timezoneIdentifier: timeZone.identifier,
            slots: slots,
            in: context
        )
    }

    private static func createEndedSession(
        for template: Template,
        startedAt: Date,
        timeZone: TimeZone,
        in context: ModelContext
    ) throws {
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: startedAt,
            timeZone: timeZone
        )
        try WorkoutSessionLifecycle.end(
            session,
            in: context,
            endedAt: startedAt.addingTimeInterval(3_600)
        )
    }

    private static func createEndedSessionWithSet(
        for template: Template,
        startedAt: Date,
        endedAt: Date,
        timeZone: TimeZone,
        in context: ModelContext
    ) throws {
        let session = try createOpenSessionWithSet(
            for: template,
            startedAt: startedAt,
            timeZone: timeZone,
            in: context
        )
        try WorkoutSessionLifecycle.end(session, in: context, endedAt: endedAt)
    }

    @discardableResult
    private static func createOpenSessionWithSet(
        for template: Template,
        startedAt: Date,
        timeZone: TimeZone,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: startedAt,
            timeZone: timeZone
        )
        guard let exerciseName = try WorkoutSessionLifecycle
            .exerciseDescriptors(for: session, in: context)
            .first?
            .name
        else {
            throw UITestFixtureError.missingExercise(template.name)
        }

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exerciseName,
            weight: 60,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: startedAt.addingTimeInterval(600),
            in: context
        )

        return session
    }

    private static func template(
        named name: String,
        in context: ModelContext
    ) throws -> Template {
        let templates = try context.fetch(FetchDescriptor<Template>())
        guard let template = templates.first(where: { $0.name == name }) else {
            throw UITestFixtureError.missingTemplate(name)
        }

        return template
    }

    private static func deleteTemplates(
        except retainedNames: Set<String>,
        in context: ModelContext
    ) throws {
        let templates = try context.fetch(FetchDescriptor<Template>())

        for template in templates where retainedNames.contains(template.name) == false {
            try TemplateLibrary.delete(template, in: context)
        }
    }

    private static func startOfDay(
        for date: Date,
        timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar.startOfDay(for: date)
    }

    private static func date(
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
            throw UITestFixtureError.invalidDate
        }

        return date
    }

    private static func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw UITestFixtureError.missingTimeZone(identifier)
        }

        return timeZone
    }
}

private enum UITestFixtureError: Error, LocalizedError {
    case unknownFixture(String)
    case missingTemplate(String)
    case missingExercise(String)
    case missingTimeZone(String)
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .unknownFixture(let name):
            "未知 UI 测试夹具：\(name)"
        case .missingTemplate(let name):
            "UI 测试夹具缺少模板：\(name)"
        case .missingExercise(let templateName):
            "UI 测试夹具模板缺少动作：\(templateName)"
        case .missingTimeZone(let identifier):
            "UI 测试夹具缺少时区：\(identifier)"
        case .invalidDate:
            "UI 测试夹具日期无效"
        }
    }
}
#endif
