import Foundation
import SwiftData

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
        guard let cycle = try TrainingScheduleEngine.activeCycle(in: context) else {
            return Week(hasCycle: false, summary: nil, days: [])
        }

        let calendar = try calendar(timezoneIdentifier: cycle.timezoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let days = try (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let plan = try TrainingScheduleEngine.plan(for: date, cycle: cycle, in: context)
            let status = offset == 0
                ? try TrainingScheduleEngine.completionStatus(for: plan, in: context)
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
            summary: try summary(for: cycle, in: context),
            days: days
        )
    }

    @MainActor
    static func todayCard(
        now: Date = Date(),
        in context: ModelContext
    ) throws -> TodayPlanCard? {
        guard try WorkoutSessionLifecycle.currentOpenSession(in: context) == nil,
              let cycle = try TrainingScheduleEngine.activeCycle(in: context) else {
            return nil
        }

        let calendar = try calendar(timezoneIdentifier: cycle.timezoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let plan = try TrainingScheduleEngine.plan(for: today, cycle: cycle, in: context)
        let status = try TrainingScheduleEngine.completionStatus(for: plan, in: context)

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
                    in: context
                ),
            colorStyle: colorStyle(for: plan),
            showsStartButton: isCompleted == false,
            startTemplate: isCompleted ? nil : template
        )
    }

    @MainActor
    private static func summary(
        for cycle: TrainingCycle,
        in context: ModelContext
    ) throws -> CycleSummary {
        let slots = try context.fetch(FetchDescriptor<TrainingCycleSlot>())
            .filter { $0.cycle?.id == cycle.id }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                return lhs.template?.name ?? "" < rhs.template?.name ?? ""
            }

        let workoutCount = slots.filter { $0.kind == .workout }.count
        let restCount = slots.count - workoutCount

        return CycleSummary(
            slotCount: slots.count,
            workoutCount: workoutCount,
            restCount: restCount,
            colorStyles: slots.map(colorStyle)
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
        if plan.isInvalidPlan {
            return .invalid
        }

        if plan.isRestDay {
            return .rest
        }

        guard let colorHex = plan.template?.colorHex else {
            return .empty
        }

        return .template(hex: colorHex)
    }

    private static func colorStyle(for slot: TrainingCycleSlot) -> ColorStyle {
        if slot.isInvalidPlan {
            return .invalid
        }

        if slot.isRestDay {
            return .rest
        }

        guard let colorHex = slot.template?.colorHex else {
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
        in context: ModelContext
    ) throws -> String? {
        guard templateStableID.isEmpty == false else {
            return nil
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let lastSession = sessions
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
