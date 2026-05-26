import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct TrainingScheduleEngineTests {
    @Test func pplSixSlotPlanMapsAcrossMonthBoundary() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 29, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: fixtures.pplSlots,
            in: context
        )

        let dates = [
            try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone),
            try date(2026, 1, 30, 12, 0, 0, timeZone: timeZone),
            try date(2026, 1, 31, 12, 0, 0, timeZone: timeZone),
            try date(2026, 2, 1, 12, 0, 0, timeZone: timeZone),
            try date(2026, 2, 2, 12, 0, 0, timeZone: timeZone),
            try date(2026, 2, 3, 12, 0, 0, timeZone: timeZone),
        ]
        let plans = try dates.map { try TrainingScheduleEngine.plan(for: $0, cycle: cycle, in: context) }

        #expect(plans.map { $0.template?.name } == ["Push A", "Pull A", "Legs A", "Push B", "Pull B", "Legs B"])
        #expect(plans.map(\.localDateKey) == [
            "2026-01-29",
            "2026-01-30",
            "2026-01-31",
            "2026-02-01",
            "2026-02-02",
            "2026-02-03",
        ])
        #expect(plans.allSatisfy { $0.source == .cycle })
    }

    @Test func pplSixSlotPlanMapsAcrossYearBoundary() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 12, 30, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: fixtures.pplSlots,
            in: context
        )

        let dates = [
            try date(2026, 12, 30, 12, 0, 0, timeZone: timeZone),
            try date(2026, 12, 31, 12, 0, 0, timeZone: timeZone),
            try date(2027, 1, 1, 12, 0, 0, timeZone: timeZone),
            try date(2027, 1, 2, 12, 0, 0, timeZone: timeZone),
            try date(2027, 1, 3, 12, 0, 0, timeZone: timeZone),
            try date(2027, 1, 4, 12, 0, 0, timeZone: timeZone),
        ]
        let plans = try dates.map { try TrainingScheduleEngine.plan(for: $0, cycle: cycle, in: context) }

        #expect(plans.map { $0.template?.name } == ["Push A", "Pull A", "Legs A", "Push B", "Pull B", "Legs B"])
        #expect(plans.map(\.localDateKey) == [
            "2026-12-30",
            "2026-12-31",
            "2027-01-01",
            "2027-01-02",
            "2027-01-03",
            "2027-01-04",
        ])
    }

    @Test func threeOnOneOffPlanMapsRestSlotAcrossMonthAndYearBoundaries() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        do {
            let context = try makeInMemoryContext()
            let fixtures = try makePPLTemplates(in: context)
            let cycle = try TrainingScheduleEngine.createCycle(
                startDate: date(2026, 1, 29, 9, 0, 0, timeZone: timeZone),
                timezoneIdentifier: timeZone.identifier,
                slots: [
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA),
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.legsA),
                    TrainingScheduleSlotDraft(kind: .rest),
                ],
                in: context
            )
            let plans = try [
                date(2026, 1, 29, 12, 0, 0, timeZone: timeZone),
                date(2026, 1, 30, 12, 0, 0, timeZone: timeZone),
                date(2026, 1, 31, 12, 0, 0, timeZone: timeZone),
                date(2026, 2, 1, 12, 0, 0, timeZone: timeZone),
            ].map { try TrainingScheduleEngine.plan(for: $0, cycle: cycle, in: context) }

            #expect(plans.map { $0.template?.name ?? "休息" } == ["Push A", "Pull A", "Legs A", "休息"])
            #expect(plans[3].isRestDay)
            #expect(plans[3].localDateKey == "2026-02-01")
        }

        do {
            let context = try makeInMemoryContext()
            let fixtures = try makePPLTemplates(in: context)
            let cycle = try TrainingScheduleEngine.createCycle(
                startDate: date(2026, 12, 30, 9, 0, 0, timeZone: timeZone),
                timezoneIdentifier: timeZone.identifier,
                slots: [
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA),
                    TrainingScheduleSlotDraft(kind: .workout, template: fixtures.legsA),
                    TrainingScheduleSlotDraft(kind: .rest),
                ],
                in: context
            )
            let plans = try [
                date(2026, 12, 30, 12, 0, 0, timeZone: timeZone),
                date(2026, 12, 31, 12, 0, 0, timeZone: timeZone),
                date(2027, 1, 1, 12, 0, 0, timeZone: timeZone),
                date(2027, 1, 2, 12, 0, 0, timeZone: timeZone),
            ].map { try TrainingScheduleEngine.plan(for: $0, cycle: cycle, in: context) }

            #expect(plans.map { $0.template?.name ?? "休息" } == ["Push A", "Pull A", "Legs A", "休息"])
            #expect(plans[3].isRestDay)
            #expect(plans[3].localDateKey == "2027-01-02")
        }
    }

    @Test func overrideTakesPriorityResetRestoresCycleAndRepeatedOverrideKeepsLatestOnly() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let targetDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: targetDate,
            timezoneIdentifier: timeZone.identifier,
            slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA),
            ],
            in: context
        )

        _ = try TrainingScheduleEngine.setOverride(
            for: targetDate,
            cycle: cycle,
            kind: .workout,
            template: fixtures.pullA,
            in: context
        )
        var plan = try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)

        #expect(plan.template?.name == "Pull A")
        #expect(plan.source == .override)

        _ = try TrainingScheduleEngine.setOverride(
            for: targetDate,
            cycle: cycle,
            kind: .workout,
            template: fixtures.legsA,
            in: context
        )
        let overridesAfterSecondSet = try fetchOverrides(in: context)
        plan = try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)

        #expect(overridesAfterSecondSet.count == 1)
        #expect(plan.template?.name == "Legs A")
        #expect(plan.source == .override)

        try TrainingScheduleEngine.resetOverride(for: targetDate, cycle: cycle, in: context)
        let overridesAfterReset = try fetchOverrides(in: context)
        plan = try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)

        #expect(overridesAfterReset.isEmpty)
        #expect(plan.template?.name == "Push A")
        #expect(plan.source == .cycle)
    }

    @Test func overrideUpsertUsesCycleTimezoneDateKey() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 9, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        let localJan2Early = try date(2026, 1, 2, 0, 30, 0, timeZone: timeZone)
        let localJan2Late = try date(2026, 1, 2, 23, 30, 0, timeZone: timeZone)

        _ = try TrainingScheduleEngine.setOverride(
            for: localJan2Early,
            cycle: cycle,
            kind: .workout,
            template: fixtures.pullA,
            in: context
        )
        _ = try TrainingScheduleEngine.setOverride(
            for: localJan2Late,
            cycle: cycle,
            kind: .workout,
            template: fixtures.legsA,
            in: context
        )

        let overrides = try fetchOverrides(in: context)
        let plan = try TrainingScheduleEngine.plan(for: localJan2Early, cycle: cycle, in: context)

        #expect(overrides.count == 1)
        #expect(overrides[0].localDateKey == "2026-01-02")
        #expect(plan.template?.name == "Legs A")
    }

    @Test func completionStatusesCoverValidInvalidRestAndNoSessionBranches() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        try assertStatus(
            expected: .completed,
            timeZone: timeZone
        ) { context, fixtures, cycle, targetDate in
            try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)
            return try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        }

        try assertStatus(
            expected: .completedWithNonPlanTemplate,
            timeZone: timeZone
        ) { context, fixtures, cycle, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
            return try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        }

        try assertStatus(
            expected: .completedWithDeletedPlanTemplate,
            timeZone: timeZone
        ) { context, fixtures, cycle, targetDate in
            try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)
            try TemplateLibrary.delete(fixtures.pushA, in: context)
            return try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        }

        try assertStatus(
            expected: .unscheduledWorkout,
            timeZone: timeZone
        ) { context, fixtures, cycle, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
            try TemplateLibrary.delete(fixtures.pushA, in: context)
            return try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        }

        try assertStatus(
            expected: .unscheduledWorkout,
            timeZone: timeZone
        ) { context, fixtures, cycle, _ in
            let restDate = try date(2026, 1, 30, 12, 0, 0, timeZone: timeZone)
            try createEndedSession(for: fixtures.pullA, startedAt: restDate, in: context, timeZone: timeZone)
            return try TrainingScheduleEngine.plan(for: restDate, cycle: cycle, in: context)
        }

        try assertStatus(
            expected: .none,
            timeZone: timeZone
        ) { context, _, cycle, targetDate in
            try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        }
    }

    @Test func matchingCompletedSessionWinsRegardlessOfSessionOrder() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        try assertStatus(
            expected: .completed,
            timeZone: timeZone
        ) { context, fixtures, cycle, targetDate in
            try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
            return try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        }

        try assertStatus(
            expected: .completed,
            timeZone: timeZone
        ) { context, fixtures, cycle, targetDate in
            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)
            try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)
            return try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        }
    }

    @Test func overrideCompletionLocksOnlyMatchingEffectivePlan() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let targetDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)
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
            in: context
        )
        try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)

        let plan = try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)
        let status = try TrainingScheduleEngine.completionStatus(for: plan, in: context)
        let canOverride = try TrainingScheduleEngine.canOverride(for: targetDate, cycle: cycle, in: context)

        #expect(plan.template?.name == "Pull A")
        #expect(status == .completed)
        #expect(canOverride == false)

        var didRejectOverride = false
        do {
            _ = try TrainingScheduleEngine.setOverride(
                for: targetDate,
                cycle: cycle,
                kind: .workout,
                template: fixtures.legsA,
                in: context
            )
        } catch TrainingScheduleEngineError.overrideLocked {
            didRejectOverride = true
        }

        var didRejectReset = false
        do {
            try TrainingScheduleEngine.resetOverride(for: targetDate, cycle: cycle, in: context)
        } catch TrainingScheduleEngineError.overrideLocked {
            didRejectReset = true
        }

        #expect(didRejectOverride)
        #expect(didRejectReset)
    }

    @Test func nonPlanAndInvalidPlanWorkoutsDoNotLockOverride() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        do {
            let context = try makeInMemoryContext()
            let fixtures = try makePPLTemplates(in: context)
            let targetDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)
            let cycle = try TrainingScheduleEngine.createCycle(
                startDate: targetDate,
                timezoneIdentifier: timeZone.identifier,
                slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
                in: context
            )

            try createEndedSession(for: fixtures.pullA, startedAt: targetDate, in: context, timeZone: timeZone)

            #expect(try TrainingScheduleEngine.canOverride(for: targetDate, cycle: cycle, in: context))
        }

        do {
            let context = try makeInMemoryContext()
            let fixtures = try makePPLTemplates(in: context)
            let targetDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)
            let cycle = try TrainingScheduleEngine.createCycle(
                startDate: targetDate,
                timezoneIdentifier: timeZone.identifier,
                slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
                in: context
            )

            try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)
            try TemplateLibrary.delete(fixtures.pushA, in: context)

            #expect(try TrainingScheduleEngine.canOverride(for: targetDate, cycle: cycle, in: context))
        }
    }

    @Test func noPlanWithEndedSessionIsUnscheduledWorkout() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let targetDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)

        try createEndedSession(for: fixtures.pushA, startedAt: targetDate, in: context, timeZone: timeZone)

        let status = try TrainingScheduleEngine.completionStatus(
            for: nil,
            localDateKey: "2026-01-29",
            timezoneIdentifier: timeZone.identifier,
            in: context
        )

        #expect(status == .unscheduledWorkout)
    }

    @Test func sessionStartedAtControlsCycleTimezoneDateBoundary() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: date(2026, 1, 1, 8, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )
        let startedAt = try date(2026, 1, 1, 23, 59, 0, timeZone: timeZone)
        let endedAt = try date(2026, 1, 2, 0, 30, 0, timeZone: timeZone)
        let session = try WorkoutSessionLifecycle.createSession(
            for: fixtures.pushA,
            in: context,
            startedAt: startedAt,
            timeZone: timeZone
        )
        try WorkoutSessionLifecycle.end(session, in: context, endedAt: endedAt)

        let jan1Plan = try TrainingScheduleEngine.plan(
            for: date(2026, 1, 1, 12, 0, 0, timeZone: timeZone),
            cycle: cycle,
            in: context
        )
        let jan2Plan = try TrainingScheduleEngine.plan(
            for: date(2026, 1, 2, 12, 0, 0, timeZone: timeZone),
            cycle: cycle,
            in: context
        )

        #expect(try TrainingScheduleEngine.completionStatus(for: jan1Plan, in: context) == .completed)
        #expect(try TrainingScheduleEngine.completionStatus(for: jan2Plan, in: context) == .none)
    }

    @Test func createCycleRejectsSecondCycleAndInvalidSlots() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let fixtures = try makePPLTemplates(in: context)
        let startDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)
        let firstCycle = try TrainingScheduleEngine.createCycle(
            startDate: startDate,
            timezoneIdentifier: timeZone.identifier,
            slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA)],
            in: context
        )

        var didRejectSecondCycle = false
        do {
            _ = try TrainingScheduleEngine.createCycle(
                startDate: startDate,
                timezoneIdentifier: timeZone.identifier,
                slots: [TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pullA)],
                in: context
            )
        } catch TrainingScheduleEngineError.activeCycleAlreadyExists {
            didRejectSecondCycle = true
        }

        #expect(didRejectSecondCycle)
        #expect(try fetchCycles(in: context).count == 1)
        #expect(try fetchCycles(in: context)[0].id == firstCycle.id)

        let invalidContext = try makeInMemoryContext()
        var didRejectEmptySlots = false
        do {
            _ = try TrainingScheduleEngine.createCycle(
                startDate: startDate,
                timezoneIdentifier: timeZone.identifier,
                slots: [],
                in: invalidContext
            )
        } catch TrainingScheduleEngineError.emptySlots {
            didRejectEmptySlots = true
        }

        var didRejectAllRestSlots = false
        do {
            _ = try TrainingScheduleEngine.createCycle(
                startDate: startDate,
                timezoneIdentifier: timeZone.identifier,
                slots: [
                    TrainingScheduleSlotDraft(kind: .rest),
                    TrainingScheduleSlotDraft(kind: .rest),
                ],
                in: invalidContext
            )
        } catch TrainingScheduleEngineError.allRestSlots {
            didRejectAllRestSlots = true
        }

        var didRejectMissingWorkoutTemplate = false
        do {
            _ = try TrainingScheduleEngine.createCycle(
                startDate: startDate,
                timezoneIdentifier: timeZone.identifier,
                slots: [TrainingScheduleSlotDraft(kind: .workout)],
                in: invalidContext
            )
        } catch TrainingScheduleEngineError.invalidWorkoutSlotTemplate {
            didRejectMissingWorkoutTemplate = true
        }

        #expect(didRejectEmptySlots)
        #expect(didRejectAllRestSlots)
        #expect(didRejectMissingWorkoutTemplate)
        #expect(try fetchCycles(in: invalidContext).isEmpty)
    }

    @Test func upgradeStyleFixtureInfersDeletedTemplateCompletionAfterBackfill() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let targetDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)
        let template = Template(name: "Push A", stableID: "template-push")
        let cycle = TrainingCycle(startDate: targetDate, timezoneIdentifier: timeZone.identifier)
        let slot = TrainingCycleSlot(cycle: cycle, orderIndex: 0, kind: .workout, template: template)
        let legacySession = WorkoutSession(
            template: template,
            templateNameSnapshot: "Push A",
            templateStableIDSnapshot: "",
            startedAt: targetDate,
            endedAt: try date(2026, 1, 29, 13, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier
        )

        context.insert(template)
        context.insert(cycle)
        context.insert(slot)
        context.insert(legacySession)
        try context.save()

        try SeedData.writeAndDedup(in: context)
        try TemplateLibrary.delete(template, in: context)

        let plan = try TrainingScheduleEngine.plan(for: targetDate, cycle: cycle, in: context)

        #expect(plan.isInvalidPlan)
        #expect(legacySession.templateStableIDSnapshot == "template-push")
        #expect(try TrainingScheduleEngine.completionStatus(for: plan, in: context) == .completedWithDeletedPlanTemplate)
    }

    private func assertStatus(
        expected: TrainingScheduleCompletionStatus,
        timeZone: TimeZone,
        makePlan: (ModelContext, PPLFixtures, TrainingCycle, Date) throws -> TrainingScheduleDayPlan
    ) throws {
        let context = try makeInMemoryContext()
        let fixtures = try makePPLTemplates(in: context)
        let targetDate = try date(2026, 1, 29, 12, 0, 0, timeZone: timeZone)
        let cycle = try TrainingScheduleEngine.createCycle(
            startDate: targetDate,
            timezoneIdentifier: timeZone.identifier,
            slots: [
                TrainingScheduleSlotDraft(kind: .workout, template: fixtures.pushA),
                TrainingScheduleSlotDraft(kind: .rest),
            ],
            in: context
        )
        let plan = try makePlan(context, fixtures, cycle, targetDate)

        #expect(try TrainingScheduleEngine.completionStatus(for: plan, in: context) == expected)
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

    private func makePPLTemplates(in context: ModelContext) throws -> PPLFixtures {
        let fixtures = PPLFixtures(
            pushA: Template(name: "Push A", stableID: "template-push-a"),
            pullA: Template(name: "Pull A", stableID: "template-pull-a"),
            legsA: Template(name: "Legs A", stableID: "template-legs-a"),
            pushB: Template(name: "Push B", stableID: "template-push-b"),
            pullB: Template(name: "Pull B", stableID: "template-pull-b"),
            legsB: Template(name: "Legs B", stableID: "template-legs-b")
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

    private func fetchCycles(in context: ModelContext) throws -> [TrainingCycle] {
        try context.fetch(FetchDescriptor<TrainingCycle>())
    }

    private func fetchOverrides(in context: ModelContext) throws -> [TrainingDayOverride] {
        try context.fetch(FetchDescriptor<TrainingDayOverride>())
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
            throw TrainingScheduleEngineTestError.invalidDate
        }

        return date
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw TrainingScheduleEngineTestError.missingTimeZone(identifier)
        }

        return timeZone
    }
}

private struct PPLFixtures {
    let pushA: Template
    let pullA: Template
    let legsA: Template
    let pushB: Template
    let pullB: Template
    let legsB: Template

    var templates: [Template] {
        [pushA, pullA, legsA, pushB, pullB, legsB]
    }

    var pplSlots: [TrainingScheduleSlotDraft] {
        templates.map { TrainingScheduleSlotDraft(kind: .workout, template: $0) }
    }
}

private enum TrainingScheduleEngineTestError: Error {
    case invalidDate
    case missingTimeZone(String)
}
