import Foundation
import SwiftData

struct TrainingScheduleDataSnapshot {
    let cycles: [TrainingCycle]
    let slots: [TrainingCycleSlot]
    let overrides: [TrainingDayOverride]
    let sessions: [WorkoutSession]
    let templates: [Template]

    init(
        cycles: [TrainingCycle],
        slots: [TrainingCycleSlot],
        overrides: [TrainingDayOverride],
        sessions: [WorkoutSession],
        templates: [Template]
    ) {
        self.cycles = cycles
        self.slots = slots
        self.overrides = overrides
        self.sessions = sessions
        self.templates = templates
    }

    @MainActor
    init(in context: ModelContext) throws {
        cycles = try context.fetch(FetchDescriptor<TrainingCycle>())
        slots = try context.fetch(FetchDescriptor<TrainingCycleSlot>())
        overrides = try context.fetch(FetchDescriptor<TrainingDayOverride>())
        sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        templates = try context.fetch(FetchDescriptor<Template>())
    }
}

extension TrainingScheduleDataSnapshot {
    var activeCycle: TrainingCycle? {
        cycles.first
    }

    var currentOpenSession: WorkoutSession? {
        sessions
            .filter { $0.endedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    func plan(
        for date: Date,
        cycle: TrainingCycle
    ) throws -> TrainingScheduleDayPlan {
        let localDateKey = try localDateKey(for: date, timezoneIdentifier: cycle.timezoneIdentifier)
        let overrideKey = TrainingDayOverride.cycleDateKey(cycleID: cycle.id, localDateKey: localDateKey)

        if let dayOverride = overrides.first(where: { $0.cycleDateKey == overrideKey }) {
            return dayPlan(
                localDateKey: localDateKey,
                timezoneIdentifier: cycle.timezoneIdentifier,
                kind: dayOverride.kind,
                template: resolvedTemplate(for: dayOverride.template),
                templateStableID: dayOverride.templateStableID,
                source: .override
            )
        }

        let slots = sortedSlots(for: cycle)
        guard slots.isEmpty == false else {
            throw TrainingScheduleEngineError.emptySlots
        }

        let slotIndex = try cycleSlotIndex(for: date, cycle: cycle, slotCount: slots.count)
        let slot = slots[slotIndex]

        return dayPlan(
            localDateKey: localDateKey,
            timezoneIdentifier: cycle.timezoneIdentifier,
            kind: slot.kind,
            template: resolvedTemplate(for: slot.template),
            templateStableID: slot.templateStableID,
            source: .cycle
        )
    }

    func sortedSlots(for cycle: TrainingCycle) -> [TrainingCycleSlot] {
        slots
            .filter { $0.cycle?.id == cycle.id }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                let lhsName = resolvedTemplate(for: lhs.template)?.name ?? ""
                let rhsName = resolvedTemplate(for: rhs.template)?.name ?? ""

                return lhsName < rhsName
            }
    }

    func resolvedTemplate(for template: Template?) -> Template? {
        guard let template else {
            return nil
        }

        return templates.first { currentTemplate in
            currentTemplate.persistentModelID == template.persistentModelID
        } ?? template
    }

    func completionStatus(
        for plan: TrainingScheduleDayPlan
    ) throws -> TrainingScheduleCompletionStatus {
        let sessions = try endedSessions(
            on: plan.localDateKey,
            timezoneIdentifier: plan.timezoneIdentifier
        )

        guard sessions.isEmpty == false else {
            return .none
        }

        if plan.isValidWorkoutPlan {
            return hasMatchingSession(templateStableID: plan.templateStableID, in: sessions)
                ? .completed
                : .completedWithNonPlanTemplate
        }

        if plan.isInvalidPlan {
            return hasMatchingSession(templateStableID: plan.templateStableID, in: sessions)
                ? .completedWithDeletedPlanTemplate
                : .unscheduledWorkout
        }

        return .unscheduledWorkout
    }

    func overrideAvailability(
        for date: Date,
        cycle: TrainingCycle,
        now: Date = Date()
    ) throws -> TrainingScheduleOverrideAvailability {
        if try isHistoricalDate(date, before: now, timezoneIdentifier: cycle.timezoneIdentifier) {
            return .locked(.historicalDate)
        }

        let plan = try plan(for: date, cycle: cycle)

        guard plan.isValidWorkoutPlan else {
            return .available
        }

        let sessions = try endedSessions(
            on: plan.localDateKey,
            timezoneIdentifier: plan.timezoneIdentifier
        )

        return hasMatchingSession(templateStableID: plan.templateStableID, in: sessions)
            ? .locked(.completedPlan)
            : .available
    }

    private func dayPlan(
        localDateKey: String,
        timezoneIdentifier: String,
        kind: TrainingPlanEntryKind,
        template: Template?,
        templateStableID: String,
        source: TrainingSchedulePlanSource
    ) -> TrainingScheduleDayPlan {
        let resolvedStableID: String

        if kind == .workout {
            resolvedStableID = templateStableID.isEmpty ? template?.stableID ?? "" : templateStableID
        } else {
            resolvedStableID = ""
        }

        return TrainingScheduleDayPlan(
            localDateKey: localDateKey,
            timezoneIdentifier: timezoneIdentifier,
            kind: kind,
            template: kind == .workout ? template : nil,
            templateStableID: resolvedStableID,
            source: source
        )
    }

    private func endedSessions(
        on localDateKey: String,
        timezoneIdentifier: String
    ) throws -> [WorkoutSession] {
        try sessions.filter { session in
            guard session.endedAt != nil else {
                return false
            }

            return try self.localDateKey(
                for: session.startedAt,
                timezoneIdentifier: timezoneIdentifier
            ) == localDateKey
        }
    }

    private func hasMatchingSession(
        templateStableID: String,
        in sessions: [WorkoutSession]
    ) -> Bool {
        guard templateStableID.isEmpty == false else {
            return false
        }

        return sessions.contains { session in
            sessionTemplateStableID(session) == templateStableID
        }
    }

    private func sessionTemplateStableID(_ session: WorkoutSession) -> String {
        if session.templateStableIDSnapshot.isEmpty == false {
            return session.templateStableIDSnapshot
        }

        return session.template?.stableID ?? ""
    }

    private func localDateKey(
        for date: Date,
        timezoneIdentifier: String
    ) throws -> String {
        let calendar = try calendar(timezoneIdentifier: timezoneIdentifier)
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            throw TrainingScheduleEngineError.invalidTimeZone
        }

        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func isHistoricalDate(
        _ date: Date,
        before now: Date,
        timezoneIdentifier: String
    ) throws -> Bool {
        let calendar = try calendar(timezoneIdentifier: timezoneIdentifier)

        return calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    private func cycleSlotIndex(
        for date: Date,
        cycle: TrainingCycle,
        slotCount: Int
    ) throws -> Int {
        let calendar = try calendar(timezoneIdentifier: cycle.timezoneIdentifier)
        let startDay = calendar.startOfDay(for: cycle.startDate)
        let targetDay = calendar.startOfDay(for: date)
        guard let dayOffset = calendar.dateComponents([.day], from: startDay, to: targetDay).day else {
            return 0
        }

        return positiveModulo(dayOffset, slotCount)
    }

    private func calendar(timezoneIdentifier: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timezoneIdentifier) else {
            throw TrainingScheduleEngineError.invalidTimeZone
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor

        return remainder >= 0 ? remainder : remainder + divisor
    }
}

enum TrainingSchedulePresentation {
    struct Week {
        let hasCycle: Bool
        let summary: CycleSummary?
        let days: [Day]
    }

    struct TodayPlanCard {
        let localDateKey: String
        let titleText: String
        let statusText: String?
        let hintText: String?
        let lastCompletionText: String?
        let colorStyle: ColorStyle
        let showsStartButton: Bool
        let startTemplate: Template?
    }

    struct CycleSummary {
        let slotCount: Int
        let workoutCount: Int
        let restCount: Int
        let colorStyles: [ColorStyle]

        var text: String {
            "\(slotCount) 槽 · \(workoutCount) 训练 / \(restCount) 休"
        }
    }

    struct Day: Identifiable {
        let id: String
        let date: Date
        let localDateKey: String
        let weekdayText: String
        let dateText: String
        let isToday: Bool
        let title: String
        let colorStyle: ColorStyle
        let isInvalidPlan: Bool
        let source: TrainingSchedulePlanSource?
        let status: TrainingScheduleCompletionStatus

        var statusText: String? {
            switch status {
            case .none:
                nil
            case .completed:
                "✓ 已完成"
            case .completedWithNonPlanTemplate:
                "✓ 已完成（非计划模板）"
            case .completedWithDeletedPlanTemplate:
                "✓ 已完成（计划模板已删除）"
            case .unscheduledWorkout:
                "计划外训练"
            }
        }
    }

    enum ColorStyle: Equatable {
        case template(hex: String)
        case rest
        case empty
        case invalid
    }

    @MainActor
    static func week(
        now: Date = Date(),
        in context: ModelContext
    ) throws -> Week {
        let data = try TrainingScheduleDataSnapshot(in: context)

        return try week(now: now, data: data)
    }

    @MainActor
    static func week(
        now: Date = Date(),
        data: TrainingScheduleDataSnapshot
    ) throws -> Week {
        guard let cycle = data.activeCycle else {
            return Week(hasCycle: false, summary: nil, days: [])
        }

        let calendar = try calendar(timezoneIdentifier: cycle.timezoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let days = try (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let plan = try data.plan(for: date, cycle: cycle)
            let status = offset == 0
                ? try data.completionStatus(for: plan)
                : .none

            return day(
                date: date,
                plan: plan,
                status: status,
                isToday: offset == 0,
                calendar: calendar
            )
        }

        return Week(
            hasCycle: true,
            summary: summary(for: cycle, data: data),
            days: days
        )
    }

    @MainActor
    static func todayCard(
        now: Date = Date(),
        in context: ModelContext
    ) throws -> TodayPlanCard? {
        let data = try TrainingScheduleDataSnapshot(in: context)

        return try todayCard(now: now, data: data)
    }

    @MainActor
    static func todayCard(
        now: Date = Date(),
        data: TrainingScheduleDataSnapshot
    ) throws -> TodayPlanCard? {
        guard data.currentOpenSession == nil,
              let cycle = data.activeCycle else {
            return nil
        }

        let calendar = try calendar(timezoneIdentifier: cycle.timezoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let plan = try data.plan(for: today, cycle: cycle)
        let status = try data.completionStatus(for: plan)

        if plan.isInvalidPlan {
            return TodayPlanCard(
                localDateKey: plan.localDateKey,
                titleText: "计划已失效",
                statusText: "计划已失效",
                hintText: nil,
                lastCompletionText: nil,
                colorStyle: .invalid,
                showsStartButton: false,
                startTemplate: nil
            )
        }

        if plan.isRestDay {
            let hasWorkout = status == .unscheduledWorkout

            return TodayPlanCard(
                localDateKey: plan.localDateKey,
                titleText: hasWorkout ? "今日：休息 · 已有训练记录" : "今日：休息",
                statusText: hasWorkout ? "计划外训练" : nil,
                hintText: nil,
                lastCompletionText: nil,
                colorStyle: .rest,
                showsStartButton: false,
                startTemplate: nil
            )
        }

        guard let template = plan.template else {
            return TodayPlanCard(
                localDateKey: plan.localDateKey,
                titleText: "计划已失效",
                statusText: "计划已失效",
                hintText: nil,
                lastCompletionText: nil,
                colorStyle: .invalid,
                showsStartButton: false,
                startTemplate: nil
            )
        }

        let isCompleted = status == .completed
        let hasOnlyNonPlanWorkout = status == .completedWithNonPlanTemplate

        return TodayPlanCard(
            localDateKey: plan.localDateKey,
            titleText: template.name,
            statusText: isCompleted ? "✓ 已完成" : nil,
            hintText: hasOnlyNonPlanWorkout ? "今日已有其他训练记录" : nil,
            lastCompletionText: isCompleted || hasOnlyNonPlanWorkout
                ? nil
                : try lastCompletionText(
                    templateStableID: plan.templateStableID,
                    before: today,
                    calendar: calendar,
                    data: data
                ),
            colorStyle: colorStyle(for: plan),
            showsStartButton: isCompleted == false,
            startTemplate: isCompleted ? nil : template
        )
    }

    private static func summary(
        for cycle: TrainingCycle,
        data: TrainingScheduleDataSnapshot
    ) -> CycleSummary {
        let slots = data.sortedSlots(for: cycle)

        let workoutCount = slots.filter { $0.kind == .workout }.count
        let restCount = slots.count - workoutCount

        return CycleSummary(
            slotCount: slots.count,
            workoutCount: workoutCount,
            restCount: restCount,
            colorStyles: slots.map { slot in
                colorStyle(
                    kind: slot.kind,
                    template: data.resolvedTemplate(for: slot.template),
                    templateStableID: slot.templateStableID
                )
            }
        )
    }

    private static func day(
        date: Date,
        plan: TrainingScheduleDayPlan,
        status: TrainingScheduleCompletionStatus,
        isToday: Bool,
        calendar: Calendar
    ) -> Day {
        let title: String

        if plan.isInvalidPlan {
            title = "计划已失效"
        } else if plan.isRestDay {
            title = "休息"
        } else {
            title = plan.template?.name ?? "计划已失效"
        }

        return Day(
            id: plan.localDateKey,
            date: date,
            localDateKey: plan.localDateKey,
            weekdayText: weekdayText(for: date, calendar: calendar),
            dateText: dateText(for: date, calendar: calendar),
            isToday: isToday,
            title: title,
            colorStyle: colorStyle(for: plan),
            isInvalidPlan: plan.isInvalidPlan,
            source: plan.source,
            status: status
        )
    }

    private static func colorStyle(for plan: TrainingScheduleDayPlan) -> ColorStyle {
        colorStyle(kind: plan.kind, template: plan.template, templateStableID: plan.templateStableID)
    }

    private static func colorStyle(
        kind: TrainingPlanEntryKind,
        template: Template?,
        templateStableID: String
    ) -> ColorStyle {
        if kind == .workout && template == nil && templateStableID.isEmpty == false {
            return .invalid
        }

        if kind == .rest {
            return .rest
        }

        guard let colorHex = template?.colorHex else {
            return .empty
        }

        return .template(hex: colorHex)
    }

    private static func weekdayText(
        for date: Date,
        calendar: Calendar
    ) -> String {
        let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = calendar.component(.weekday, from: date)

        return weekdaySymbols[max(0, min(weekday - 1, weekdaySymbols.count - 1))]
    }

    private static func dateText(
        for date: Date,
        calendar: Calendar
    ) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        return "\(month)/\(day)"
    }

    @MainActor
    private static func lastCompletionText(
        templateStableID: String,
        before today: Date,
        calendar: Calendar,
        data: TrainingScheduleDataSnapshot
    ) throws -> String? {
        guard templateStableID.isEmpty == false else {
            return nil
        }

        let lastSession = data.sessions
            .compactMap { session -> (session: WorkoutSession, endedAt: Date)? in
                guard let endedAt = session.endedAt,
                      sessionTemplateStableID(session) == templateStableID else {
                    return nil
                }

                guard calendar.startOfDay(for: endedAt) < today else {
                    return nil
                }

                return (session, endedAt)
            }
            .sorted { lhs, rhs in
                if lhs.endedAt != rhs.endedAt {
                    return lhs.endedAt > rhs.endedAt
                }

                return lhs.session.startedAt > rhs.session.startedAt
            }
            .first

        guard let endedAt = lastSession?.endedAt else {
            return nil
        }

        return "上次完成 · \(longDateText(for: endedAt, calendar: calendar))"
    }

    private static func longDateText(
        for date: Date,
        calendar: Calendar
    ) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        return "\(month) 月 \(day) 日"
    }

    private static func sessionTemplateStableID(_ session: WorkoutSession) -> String {
        if session.templateStableIDSnapshot.isEmpty == false {
            return session.templateStableIDSnapshot
        }

        return session.template?.stableID ?? ""
    }

    private static func calendar(timezoneIdentifier: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timezoneIdentifier) else {
            throw TrainingScheduleEngineError.invalidTimeZone
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar
    }
}
