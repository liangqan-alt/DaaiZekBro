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
                now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
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
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
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

    @Test func todayPlanCardReturnsNilWithoutCycleAndWhenWorkoutIsOpen() throws {
        let noCycleContext = try makeInMemoryContext()

        #expect(try TrainingSchedulePresentation.todayCard(
            now: Date(timeIntervalSince1970: 1_767_225_600),
            in: noCycleContext
        ) == nil)

        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        _ = try WorkoutSessionLifecycle.createSession(
            for: fixtures.pushA,
            in: context,
            startedAt: date(2026, 1, 1, 10, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        #expect(try TrainingSchedulePresentation.todayCard(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        ) == nil)
    }

    @Test func todayPlanCardTrainingDayShowsTemplateLastCompletionAndStartAction() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2025, 12, 30, 12, 0, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )

        let card = try #require(try TrainingSchedulePresentation.todayCard(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        ))

        #expect(card.localDateKey == "2026-01-01")
        #expect(card.titleText == "Push A")
        #expect(card.statusText == nil)
        #expect(card.hintText == nil)
        #expect(card.lastCompletionText == "上次完成 · 12 月 30 日")
        #expect(card.colorStyle == .template(hex: "#D86838"))
        #expect(card.showsStartButton)
        #expect(card.startTemplate?.persistentModelID == fixtures.pushA.persistentModelID)
    }

    @Test func todayPlanCardCoversCompletedOffPlanRestAndInvalidStates() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        try assertTodayPlanCard(timeZone: timeZone) { context, fixtures, targetDate in
            try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)
        } verify: { card in
            #expect(card.titleText == "Push A")
            #expect(card.statusText == "✓ 已完成")
            #expect(card.showsStartButton == false)
        }

        try assertTodayPlanCard(timeZone: timeZone) { context, fixtures, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
        } verify: { card in
            #expect(card.titleText == "Push A")
            #expect(card.statusText == nil)
            #expect(card.hintText == "今日已有其他训练记录")
            #expect(card.showsStartButton)
        }

        try assertTodayPlanCard(
            timeZone: timeZone,
            slots: [
                TrainingScheduleSlotDraft(kind: .rest),
                TrainingScheduleSlotDraft(kind: .workout, template: nil),
            ]
        ) { _, _, _ in
        } verify: { card in
            #expect(card.titleText == "今日：休息")
            #expect(card.statusText == nil)
            #expect(card.colorStyle == .rest)
            #expect(card.showsStartButton == false)
        }

        try assertTodayPlanCard(
            timeZone: timeZone,
            slots: [
                TrainingScheduleSlotDraft(kind: .rest),
                TrainingScheduleSlotDraft(kind: .workout, template: nil),
            ]
        ) { context, fixtures, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
        } verify: { card in
            #expect(card.titleText == "今日：休息 · 已有训练记录")
            #expect(card.statusText == "计划外训练")
            #expect(card.showsStartButton == false)
        }

        try assertTodayPlanCard(timeZone: timeZone) { context, fixtures, _ in
            try TemplateLibrary.delete(fixtures.pushA, in: context)
        } verify: { card in
            #expect(card.titleText == "计划已失效")
            #expect(card.statusText == "计划已失效")
            #expect(card.colorStyle == .invalid)
            #expect(card.showsStartButton == false)
        }
    }

    @Test func todayPlanCardUsesCycleTimezoneForTodayAndCompletionStatus() throws {
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

        let card = try #require(try TrainingSchedulePresentation.todayCard(
            now: date(2026, 1, 1, 16, 30, 0, timeZone: utc),
            in: context
        ))

        #expect(card.localDateKey == "2026-01-02")
        #expect(card.statusText == "✓ 已完成")
        #expect(card.showsStartButton == false)
    }

    @Test func todayPlanCardLastCompletionUsesSameTemplateStableIdentityOnly() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2025, 12, 28, 12, 0, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )
        try createEndedSession(
            for: fixtures.pullA,
            startedAt: date(2025, 12, 31, 12, 0, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2025, 12, 30, 12, 0, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )

        let card = try #require(try TrainingSchedulePresentation.todayCard(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        ))

        #expect(card.lastCompletionText == "上次完成 · 12 月 30 日")
    }

    @Test func todayPlanCardLastCompletionUsesEndedAtForBoundarySortingAndDateText() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2025, 12, 31, 23, 30, 0, timeZone: timeZone),
            endedAt: date(2026, 1, 1, 0, 30, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )
        try createEndedSession(
            for: fixtures.pushA,
            startedAt: date(2025, 12, 30, 10, 0, 0, timeZone: timeZone),
            endedAt: date(2025, 12, 31, 23, 50, 0, timeZone: timeZone),
            in: context,
            timeZone: timeZone
        )

        let card = try #require(try TrainingSchedulePresentation.todayCard(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        ))

        #expect(card.lastCompletionText == "上次完成 · 12 月 31 日")
    }

    @Test func completingPlanStartedWorkoutUpdatesTodayCardAndWeekStatus() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        let targetDate = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        _ = try TrainingScheduleEngine.createCycle(
            startDate: targetDate,
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )

        let readyCard = try #require(try TrainingSchedulePresentation.todayCard(now: targetDate, in: context))
        let template = try #require(readyCard.startTemplate)
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: targetDate,
            timeZone: timeZone
        )
        try WorkoutSessionLifecycle.end(
            session,
            in: context,
            endedAt: targetDate.addingTimeInterval(3_600)
        )

        let completedCard = try #require(try TrainingSchedulePresentation.todayCard(now: targetDate, in: context))
        let week = try TrainingSchedulePresentation.week(now: targetDate, in: context)

        #expect(completedCard.statusText == "✓ 已完成")
        #expect(completedCard.showsStartButton == false)
        #expect(week.days[0].statusText == "✓ 已完成")
    }

    @Test func todayOverrideSyncsWeekAndTodayCard() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        let targetDate = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: targetDate,
            timezoneIdentifier: timeZone.identifier,
            slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.legsA),
            ],
            in: context
        )
        _ = try TrainingScheduleEngine.setOverride(
            for: targetDate,
            cycle: cycle,
            kind: .workout,
            template: fixtures.pullA,
            now: targetDate,
            in: context
        )

        let week = try TrainingSchedulePresentation.week(now: targetDate, in: context)
        let card = try #require(try TrainingSchedulePresentation.todayCard(now: targetDate, in: context))

        #expect(week.days[0].title == "Pull A")
        #expect(week.days[0].source == .override)
        #expect(week.days[0].statusText == nil)
        #expect(week.days[0].colorStyle == .template(hex: "#4E7BA6"))
        #expect(card.titleText == "Pull A")
        #expect(card.statusText == nil)
        #expect(card.colorStyle == .template(hex: "#4E7BA6"))
        #expect(card.startTemplate?.persistentModelID == fixtures.pullA.persistentModelID)
    }

    @Test func startFlowAfterTodayOverrideUsesOverrideTemplateAndCompletionUpdatesPresentation() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        let targetDate = try date(2026, 1, 1, 12, 0, 0, timeZone: timeZone)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: targetDate,
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        _ = try TrainingScheduleEngine.setOverride(
            for: targetDate,
            cycle: cycle,
            kind: .workout,
            template: fixtures.pullA,
            now: targetDate,
            in: context
        )

        let readyCard = try #require(try TrainingSchedulePresentation.todayCard(now: targetDate, in: context))
        let template = try #require(readyCard.startTemplate)
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: targetDate,
            timeZone: timeZone
        )
        try WorkoutSessionLifecycle.end(
            session,
            in: context,
            endedAt: targetDate.addingTimeInterval(3_600)
        )

        let completedCard = try #require(try TrainingSchedulePresentation.todayCard(now: targetDate, in: context))
        let week = try TrainingSchedulePresentation.week(now: targetDate, in: context)

        #expect(template.persistentModelID == fixtures.pullA.persistentModelID)
        #expect(session.templateStableIDSnapshot == fixtures.pullA.stableID)
        #expect(completedCard.titleText == "Pull A")
        #expect(completedCard.statusText == "✓ 已完成")
        #expect(completedCard.showsStartButton == false)
        #expect(week.days[0].title == "Pull A")
        #expect(week.days[0].statusText == "✓ 已完成")
    }

    @Test func deletingCycleHidesTodayPlanCard() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makeTemplates(in: context)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )

        #expect(try TrainingSchedulePresentation.todayCard(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        ) != nil)

        try TrainingScheduleEngine.deleteCycle(cycle, in: context)

        #expect(try TrainingSchedulePresentation.todayCard(
            now: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            in: context
        ) == nil)
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

    private func assertTodayPlanCard(
        timeZone: TimeZone,
        slots slotBuilder: [TrainingScheduleSlotDraft]? = nil,
        arrange: (ModelContext, PresentationFixtures, Date) throws -> Void,
        verify: (TrainingSchedulePresentation.TodayPlanCard) throws -> Void
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

        let card = try #require(try TrainingSchedulePresentation.todayCard(now: targetDate, in: context))

        try verify(card)
    }

    @discardableResult
    private func createEndedSession(
        for template: Template,
        startedAt: Date,
        endedAt: Date? = nil,
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
            endedAt: endedAt ?? startedAt.addingTimeInterval(3_600)
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
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

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
