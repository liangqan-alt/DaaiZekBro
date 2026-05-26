import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct TrainingSchedulePresentationTests {
    @Test func weekReturnsEmptyStateWithoutCycle() throws {
        let context = try makeInMemoryContext()
        let week = try TrainingSchedulePresentation.week(
            now: Date(timeIntervalSince1970: 1_767_225_600),
            in: context
        )

        #expect(week.hasCycle == false)
        #expect(week.summary == nil)
        #expect(week.days.isEmpty)
    }

    @Test func weekListsSevenDaysWithColorsRestAndTodayHighlight() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA),
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.legsA),
                TrainingScheduleSlotDraft(kind: .rest),
            ],
            in: context
        )

        let week = try TrainingSchedulePresentation.week(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        )

        #expect(week.hasCycle)
        #expect(week.summary?.text == "4 槽 · 3 训练 / 1 休")
        #expect(week.days.count == 7)
        #expect(week.days.map(\.title) == ["Push A", "Pull A", "Legs A", "休息", "Push A", "Pull A", "Legs A"])
        #expect(week.days[0].isToday)
        #expect(week.days.dropFirst().allSatisfy { $0.isToday == false })
        #expect(week.days[0].colorStyle == .template(hex: "#D86838"))
        #expect(week.days[1].colorStyle == .template(hex: "#4E7BA6"))
        #expect(week.days[2].colorStyle == .template(hex: "#5C8A3A"))
        #expect(week.days[3].colorStyle == .rest)
        #expect(week.days.allSatisfy { $0.statusText == nil })
    }

    @Test func todayShowsCompletionStatusButFutureDaysDoNot() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA),
            ],
            in: context
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )
        try createEndedSession(
            for: fixtures.pullA,
            startedAt: date(2026, 1, 2, 12, 0, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )

        let week = try TrainingSchedulePresentation.week(
            now: date(2026, 1, 1, 18, 0, 0, timeZone: timeZone),
            in: context
        )

        #expect(week.days[0].statusText == "✓ 已完成")
        #expect(week.days[1].statusText == nil)
    }

    @Test func todayCompletionStatusTextCoversNonPlanInvalidRestAndNoSessionBranches() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        try assertTodayStatusText("✓ 已完成（非计划模板）", timeZone: timeZone) { context, fixtures, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
        }

        try assertTodayStatusText("✓ 已完成（计划模板已删除）", timeZone: timeZone) { context, fixtures, targetDate in
            try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)
            try TemplateLibrary.delete(fixtures.pushA, in: context)
        }

        try assertTodayStatusText("计划外训练", timeZone: timeZone) { context, fixtures, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
            try TemplateLibrary.delete(fixtures.pushA, in: context)
        }

        try assertTodayStatusText("计划外训练", timeZone: timeZone, slots: [
            TrainingScheduleSlotDraft(kind: .rest),
            TrainingScheduleSlotDraft(kind: .workout, template: nil),
        ]) { context, fixtures, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
        }

        try assertTodayStatusText(nil, timeZone: timeZone) { _, _, _ in }
    }

    @Test func deletedTemplateInvalidatesOnlyAffectedSlotAndOverrideDays() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        do {
            let context = try makeInMemoryContext()
            let fixtures = try makeTemplates(in: context)
            _ = try TrainingScheduleEngine.createCycle(
                startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
                timezoneIdentifier: timeZone.identifier,
                slots: [
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA),
                ],
                in: context
            )

            try TemplateLibrary.delete(fixtures.pushA, in: context)

            let week = try TrainingSchedulePresentation.week(
                now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
                in: context
            )

            #expect(week.days[0].title == "计划已失效")
            #expect(week.days[0].colorStyle == .invalid)
            #expect(week.days[1].title == "Pull A")
        }

        do {
            let context = try makeInMemoryContext()
            let fixtures = try makeTemplates(in: context)
            let cycle = try TrainingScheduleEngine.createCycle(
                startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
                timezoneIdentifier: timeZone.identifier,
                slots: [
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.legsA),
                ],
                in: context
            )
            _ = try TrainingScheduleEngine.setOverride(
                for: date(2026, 1, 2, 12, 0, 0, timeZone: timeZone),
                cycle: cycle,
                kind: .workout,
                template: fixtures.pullA,
                in: context
            )

            try TemplateLibrary.delete(fixtures.pullA, in: context)

            let week = try TrainingSchedulePresentation.week(
                now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
                in: context
            )

            #expect(week.days[0].title == "Push A")
            #expect(week.days[1].title == "计划已失效")
            #expect(week.days[2].title == "Push A")
        }
    }

    @Test func templateRenameUpdatesSlotAndOverrideNamesWithoutChangingIdentityMatching() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.legsA),
            ],
            in: context
        )
        _ = try TrainingScheduleEngine.setOverride(
            for: date(2026, 1, 2, 12, 0, 0, timeZone: timeZone),
            cycle: cycle,
            kind: .workout,
            template: fixtures.pullA,
            in: context
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )

        try TemplateLibrary.rename(fixtures.pushA, name: "Push Prime", in: context)
        try TemplateLibrary.rename(fixtures.pullA, name: "Pull Prime", in: context)

        let week = try TrainingSchedulePresentation.week(
            now: date(2026, 1, 1, 18, 0, 0, timeZone: timeZone),
            in: context
        )

        #expect(week.days[0].title == "Push Prime")
        #expect(week.days[0].statusText == "✓ 已完成")
        #expect(week.days[1].title == "Pull Prime")
    }

    @Test func userTemplateWithoutColorUsesEmptyStyle() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let custom = Template(name: "Custom", stableID: "template-custom")
        context.insert(custom)
        try context.save()

        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: custom)],
            in: context
        )

        let week = try TrainingSchedulePresentation.week(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        )

        #expect(week.days[0].colorStyle == .empty)
    }

    @Test func todayUsesCycleTimezoneWhenDeviceInstantFallsOnDifferentUTCDate() throws {
        let context = try makeInMemoryContext()
        let cycleTimeZone = try requiredTimeZone("Asia/Shanghai")
        let utc = try requiredTimeZone("UTC")
        let fixtures = try makeTemplates(in: context)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 2, 0, 0, 0, timeZone: cycleTimeZone),
            timezoneIdentifier: cycleTimeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2026, 1, 2, 0, 10, 0, timeZone: cycleTimeZone),
            in: context,
            timeZone: cycleTimeZone
        )

        let week = try TrainingSchedulePresentation.week(
            now: date(2026, 1, 1, 16, 30, 0, timeZone: utc),
            in: context
        )

        #expect(week.days[0].localDateKey == "2026-01-02")
        #expect(week.days[0].statusText == "✓ 已完成")
    }

    private func assertTodayStatusText(
        _ expectedText: String?,
        timeZone: TimeZone,
        slots slotBuilder: [TrainingScheduleSlotDraft]? = nil,
        arrange: (ModelContext, PresentationFixtures, Date) throws -> Void
    ) throws {
        let context = try makeInMemoryContext()
        let fixtures = try makeTemplates(in: context)
        let targetDate = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let slots = slotBuilder ?? [
            TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
            TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA),
        ]

        _ = try TrainingScheduleEngine.createCycle(
            startDate: targetDate,
            timezoneIdentifier: timeZone.identifier,
            slots: slots.map { draft in
                if draft.kind == .workout && draft.template == nil {
                    return TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)
                }

                return draft
            },
            in: context
        )
        try arrange(context, fixtures, targetDate)

        let week = try TrainingSchedulePresentation.week(now: targetDate, in: context)

        #expect(week.days[0].statusText == expectedText)
    }

    @discardableResult
    private func createEndedSession(
        for template: Template,
        startedAt: Date,
        in context: ModelContext,
        timeZone: TimeZone
    ) throws -> WorkoutSession {
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

        return session
    }

    private func makeTemplates(in context: ModelContext) throws -> PresentationFixtures {
        let fixtures = PresentationFixtures(
            pushA: Template(name: "Push A", stableID: "template-push-a", colorHex: "#D86838"),
            pullA: Template(name: "Pull A", stableID: "template-pull-a", colorHex: "#4E7BA6"),
            legsA: Template(name: "Legs A", stableID: "template-legs-a", colorHex: "#5C8A3A")
        )

        for template in fixtures.templates {
            context.insert(template)
        }
        try context.save()

        return fixtures
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
            throw TrainingSchedulePresentationTestError.invalidDate
        }

        return date
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw TrainingSchedulePresentationTestError.missingTimeZone(identifier)
        }

        return timeZone
    }
}

private struct PresentationFixtures {
    let pushA: Template
    let pullA: Template
    let legsA: Template

    var templates: [Template] {
        [pushA, pullA, legsA]
    }
}

private enum TrainingSchedulePresentationTestError: Error {
    case invalidDate
    case missingTimeZone(String)
}
