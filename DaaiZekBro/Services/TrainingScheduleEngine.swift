import Foundation
import SwiftData

enum TrainingScheduleEngineError: Error, LocalizedError, Equatable {
    case activeCycleAlreadyExists
    case emptySlots
    case allRestSlots
    case invalidWorkoutSlotTemplate
    case invalidTimeZone
    case overrideLocked

    var errorDescription: String? {
        switch self {
        case .activeCycleAlreadyExists:
            "已有训练周期，请先删除后再新建"
        case .emptySlots:
            "训练周期至少需要一个槽位"
        case .allRestSlots:
            "训练周期至少需要一个训练模板"
        case .invalidWorkoutSlotTemplate:
            "训练日槽位缺少训练模板"
        case .invalidTimeZone:
            "训练周期时区无效"
        case .overrideLocked:
            "当天计划已完成，不能覆盖"
        }
    }
}

struct TrainingScheduleSlotDraft {
    let kind: TrainingPlanEntryKind
    let template: Template?

    init(kind: TrainingPlanEntryKind, template: Template? = nil) {
        self.kind = kind
        self.template = template
    }
}

enum TrainingSchedulePlanSource: Equatable {
    case cycle
    case override
}

struct TrainingScheduleDayPlan {
    let localDateKey: String
    let timezoneIdentifier: String
    let kind: TrainingPlanEntryKind
    let template: Template?
    let templateStableID: String
    let source: TrainingSchedulePlanSource

    var isRestDay: Bool {
        kind == .rest
    }

    var isInvalidPlan: Bool {
        kind == .workout && template == nil && templateStableID.isEmpty == false
    }

    var isValidWorkoutPlan: Bool {
        kind == .workout && template != nil && templateStableID.isEmpty == false
    }
}

enum TrainingScheduleCompletionStatus: Equatable {
    case none
    case completed
    case completedWithNonPlanTemplate
    case completedWithDeletedPlanTemplate
    case unscheduledWorkout
}

@MainActor
enum TrainingScheduleEngine {
    @discardableResult
    static func createCycle(
        startDate: Date,
        timezoneIdentifier: String,
        slots: [TrainingScheduleSlotDraft],
        in context: ModelContext
    ) throws -> TrainingCycle {
        guard TimeZone(identifier: timezoneIdentifier) != nil else {
            throw TrainingScheduleEngineError.invalidTimeZone
        }

        let existingCycles = try context.fetch(FetchDescriptor<TrainingCycle>())
        guard existingCycles.isEmpty else {
            throw TrainingScheduleEngineError.activeCycleAlreadyExists
        }

        try validate(slots)

        let cycle = TrainingCycle(startDate: startDate, timezoneIdentifier: timezoneIdentifier)
        context.insert(cycle)

        for (index, slotDraft) in slots.enumerated() {
            context.insert(
                TrainingCycleSlot(
                    cycle: cycle,
                    orderIndex: index,
                    kind: slotDraft.kind,
                    template: slotDraft.kind == .workout ? slotDraft.template : nil
                )
            )
        }

        try context.save()

        return cycle
    }

    static func activeCycle(in context: ModelContext) throws -> TrainingCycle? {
        try context.fetch(FetchDescriptor<TrainingCycle>()).first
    }

    static func plan(for date: Date, in context: ModelContext) throws -> TrainingScheduleDayPlan? {
        guard let cycle = try activeCycle(in: context) else {
            return nil
        }

        return try plan(for: date, cycle: cycle, in: context)
    }

    static func plan(
        for date: Date,
        cycle: TrainingCycle,
        in context: ModelContext
    ) throws -> TrainingScheduleDayPlan {
        let localDateKey = try localDateKey(for: date, timezoneIdentifier: cycle.timezoneIdentifier)
        let overrideKey = TrainingDayOverride.cycleDateKey(cycleID: cycle.id, localDateKey: localDateKey)
        let overrides = try context.fetch(FetchDescriptor<TrainingDayOverride>())

        if let dayOverride = overrides.first(where: { $0.cycleDateKey == overrideKey }) {
            return dayPlan(
                localDateKey: localDateKey,
                timezoneIdentifier: cycle.timezoneIdentifier,
                kind: dayOverride.kind,
                template: dayOverride.template,
                templateStableID: dayOverride.templateStableID,
                source: .override
            )
        }

        let slots = try sortedSlots(for: cycle, in: context)
        guard slots.isEmpty == false else {
            throw TrainingScheduleEngineError.emptySlots
        }

        let slotIndex = try cycleSlotIndex(for: date, cycle: cycle, slotCount: slots.count)
        let slot = slots[slotIndex]

        return dayPlan(
            localDateKey: localDateKey,
            timezoneIdentifier: cycle.timezoneIdentifier,
            kind: slot.kind,
            template: slot.template,
            templateStableID: slot.templateStableID,
            source: .cycle
        )
    }

    @discardableResult
    static func setOverride(
        for date: Date,
        cycle: TrainingCycle,
        kind: TrainingPlanEntryKind,
        template: Template?,
        in context: ModelContext
    ) throws -> TrainingDayOverride {
        if kind == .workout && template == nil {
            throw TrainingScheduleEngineError.invalidWorkoutSlotTemplate
        }

        guard try canOverride(for: date, cycle: cycle, in: context) else {
            throw TrainingScheduleEngineError.overrideLocked
        }

        let localDateKey = try localDateKey(for: date, timezoneIdentifier: cycle.timezoneIdentifier)

        return try TrainingDayOverride.upsert(
            cycle: cycle,
            localDateKey: localDateKey,
            kind: kind,
            template: kind == .workout ? template : nil,
            in: context
        )
    }

    static func resetOverride(
        for date: Date,
        cycle: TrainingCycle,
        in context: ModelContext
    ) throws {
        guard try canOverride(for: date, cycle: cycle, in: context) else {
            throw TrainingScheduleEngineError.overrideLocked
        }

        let localDateKey = try localDateKey(for: date, timezoneIdentifier: cycle.timezoneIdentifier)
        let overrideKey = TrainingDayOverride.cycleDateKey(cycleID: cycle.id, localDateKey: localDateKey)
        let overrides = try context.fetch(FetchDescriptor<TrainingDayOverride>())

        for dayOverride in overrides where dayOverride.cycleDateKey == overrideKey {
            context.delete(dayOverride)
        }

        try context.save()
    }

    static func completionStatus(
        for plan: TrainingScheduleDayPlan,
        in context: ModelContext
    ) throws -> TrainingScheduleCompletionStatus {
        try completionStatus(
            for: plan,
            localDateKey: plan.localDateKey,
            timezoneIdentifier: plan.timezoneIdentifier,
            in: context
        )
    }

    static func completionStatus(
        for plan: TrainingScheduleDayPlan?,
        localDateKey: String,
        timezoneIdentifier: String,
        in context: ModelContext
    ) throws -> TrainingScheduleCompletionStatus {
        let sessions = try endedSessions(
            on: localDateKey,
            timezoneIdentifier: timezoneIdentifier,
            in: context
        )

        guard sessions.isEmpty == false else {
            return .none
        }

        guard let plan else {
            return .unscheduledWorkout
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

    static func canOverride(
        for date: Date,
        cycle: TrainingCycle,
        in context: ModelContext
    ) throws -> Bool {
        let plan = try plan(for: date, cycle: cycle, in: context)

        guard plan.isValidWorkoutPlan else {
            return true
        }

        let sessions = try endedSessions(
            on: plan.localDateKey,
            timezoneIdentifier: plan.timezoneIdentifier,
            in: context
        )

        return hasMatchingSession(templateStableID: plan.templateStableID, in: sessions) == false
    }

    private static func validate(_ slots: [TrainingScheduleSlotDraft]) throws {
        guard slots.isEmpty == false else {
            throw TrainingScheduleEngineError.emptySlots
        }

        guard slots.contains(where: { $0.kind == .workout }) else {
            throw TrainingScheduleEngineError.allRestSlots
        }

        guard slots.allSatisfy({ $0.kind == .rest || $0.template != nil }) else {
            throw TrainingScheduleEngineError.invalidWorkoutSlotTemplate
        }
    }

    private static func sortedSlots(
        for cycle: TrainingCycle,
        in context: ModelContext
    ) throws -> [TrainingCycleSlot] {
        try context.fetch(FetchDescriptor<TrainingCycleSlot>())
            .filter { $0.cycle?.id == cycle.id }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }

                return lhs.template?.name ?? "" < rhs.template?.name ?? ""
            }
    }

    private static func cycleSlotIndex(
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

    private static func dayPlan(
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

    private static func endedSessions(
        on localDateKey: String,
        timezoneIdentifier: String,
        in context: ModelContext
    ) throws -> [WorkoutSession] {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        return try sessions.filter { session in
            guard session.endedAt != nil else {
                return false
            }

            return try self.localDateKey(
                for: session.startedAt,
                timezoneIdentifier: timezoneIdentifier
            ) == localDateKey
        }
    }

    private static func hasMatchingSession(
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

    private static func sessionTemplateStableID(_ session: WorkoutSession) -> String {
        if session.templateStableIDSnapshot.isEmpty == false {
            return session.templateStableIDSnapshot
        }

        return session.template?.stableID ?? ""
    }

    private static func localDateKey(
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

    private static func calendar(timezoneIdentifier: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timezoneIdentifier) else {
            throw TrainingScheduleEngineError.invalidTimeZone
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor

        return remainder >= 0 ? remainder : remainder + divisor
    }
}
