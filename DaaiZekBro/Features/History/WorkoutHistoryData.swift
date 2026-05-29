import Foundation

struct WorkoutHistoryMonthSection: Identifiable, Equatable {
    let id: WorkoutHistoryMonth
    let rows: [WorkoutHistoryRow]

    var title: String {
        "\(id.year) 年 \(id.month) 月"
    }
}

struct WorkoutHistoryRow: Identifiable, Equatable {
    let summary: WorkoutHistorySessionSummary
    let showsStartTime: Bool
    let now: Date

    var id: UUID {
        summary.id
    }

    var title: String {
        WorkoutHistoryDisplay.listTitle(for: summary, showsStartTime: showsStartTime, now: now)
    }
}

struct WorkoutHistorySessionSummary: Identifiable, Equatable {
    let id: UUID
    let templateName: String
    let startedAt: Date
    let endedAt: Date?
    let timezoneIdentifier: String
    let setCount: Int
}

struct WorkoutHistoryMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    static func < (lhs: WorkoutHistoryMonth, rhs: WorkoutHistoryMonth) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }

        return lhs.month < rhs.month
    }
}

struct WorkoutHistoryExerciseGroup: Identifiable {
    let id: String
    let exerciseName: String
    let weightUnit: WeightUnit
    let sets: [WorkoutSet]
}

enum WorkoutHistoryData {
    static func sections(
        sessions: [WorkoutSession],
        sets: [WorkoutSet],
        now: Date,
        calendar: Calendar
    ) -> [WorkoutHistoryMonthSection] {
        sections(for: summaries(sessions: sessions, sets: sets), now: now, calendar: calendar)
    }

    static func sections(
        for summaries: [WorkoutHistorySessionSummary],
        now: Date,
        calendar: Calendar
    ) -> [WorkoutHistoryMonthSection] {
        let orderedSummaries = summaries.sorted { $0.startedAt > $1.startedAt }
        let dayCounts = Dictionary(grouping: orderedSummaries) { summary in
            dayKey(for: summary)
        }
            .mapValues(\.count)
        let groupedByMonth = Dictionary(grouping: orderedSummaries) { summary in
            month(for: summary, calendar: calendar)
        }

        return groupedByMonth
            .keys
            .sorted(by: >)
            .map { month in
                let rows = (groupedByMonth[month] ?? [])
                    .sorted { $0.startedAt > $1.startedAt }
                    .map { summary in
                        WorkoutHistoryRow(
                            summary: summary,
                            showsStartTime: dayCounts[dayKey(for: summary), default: 0] > 1,
                            now: now
                        )
                    }

                return WorkoutHistoryMonthSection(id: month, rows: rows)
            }
    }

    static func summaries(sessions: [WorkoutSession], sets: [WorkoutSet]) -> [WorkoutHistorySessionSummary] {
        let setsBySessionID = Dictionary(grouping: sets.compactMap { set -> (UUID, WorkoutSet)? in
            guard let sessionID = set.session?.id else {
                return nil
            }

            return (sessionID, set)
        }, by: \.0)

        return sessions.compactMap { session in
            let setCount = setsBySessionID[session.id]?.count ?? 0

            guard setCount > 0 else {
                return nil
            }

            return WorkoutHistorySessionSummary(
                id: session.id,
                templateName: templateName(for: session),
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                timezoneIdentifier: session.timezoneIdentifier,
                setCount: setCount
            )
        }
    }

    static func exerciseGroups(
        for sessionID: UUID,
        sets: [WorkoutSet],
        exerciseDescriptors: [WorkoutSessionExerciseDescriptor] = []
    ) -> [WorkoutHistoryExerciseGroup] {
        let orderedSets = sets
            .filter { $0.session?.id == sessionID }
            .sorted { lhs, rhs in
                areSetsInDisplayOrder(lhs, rhs)
            }
        let descriptorUnits = descriptorUnitsByGroupID(exerciseDescriptors)
        var groups: [WorkoutHistoryExerciseGroup] = []

        for set in orderedSets {
            let exerciseName = exerciseName(for: set)
            let groupID = exerciseGroupID(orderIndex: set.exerciseOrderIndex, exerciseName: exerciseName)

            if let index = groups.firstIndex(where: { $0.id == groupID }) {
                var updatedSets = groups[index].sets
                updatedSets.append(set)
                groups[index] = WorkoutHistoryExerciseGroup(
                    id: groupID,
                    exerciseName: exerciseName,
                    weightUnit: groups[index].weightUnit,
                    sets: updatedSets
                )
            } else {
                groups.append(
                    WorkoutHistoryExerciseGroup(
                        id: groupID,
                        exerciseName: exerciseName,
                        weightUnit: descriptorUnits[groupID] ?? set.exercise?.weightUnit ?? .kilograms,
                        sets: [set]
                    )
                )
            }
        }

        return groups
    }

    static func templateName(for session: WorkoutSession) -> String {
        if session.templateNameSnapshot.isEmpty == false {
            return session.templateNameSnapshot
        }

        if let templateName = session.template?.name, templateName.isEmpty == false {
            return templateName
        }

        return "未命名训练"
    }

    static func exerciseName(for set: WorkoutSet) -> String {
        if set.exerciseNameSnapshot.isEmpty == false {
            return set.exerciseNameSnapshot
        }

        return set.exercise?.name ?? "未命名动作"
    }

    static func setTitle(for set: WorkoutSet) -> String {
        let sideText = set.side.map { " · \(WorkoutHistoryDisplay.sideText($0))" } ?? ""

        return "第 \(set.setIndex) 组\(sideText)"
    }

    private static func month(
        for summary: WorkoutHistorySessionSummary,
        calendar: Calendar
    ) -> WorkoutHistoryMonth {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: summary.timezoneIdentifier) ?? calendar.timeZone
        let components = calendar.dateComponents([.year, .month], from: summary.startedAt)

        return WorkoutHistoryMonth(year: components.year ?? 1, month: components.month ?? 1)
    }

    private static func dayKey(for summary: WorkoutHistorySessionSummary) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: summary.timezoneIdentifier) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: summary.startedAt)

        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(calendar.timeZone.identifier)"
    }

    private static func descriptorUnitsByGroupID(
        _ descriptors: [WorkoutSessionExerciseDescriptor]
    ) -> [String: WeightUnit] {
        var unitsByGroupID: [String: WeightUnit] = [:]

        for descriptor in descriptors {
            let groupID = exerciseGroupID(orderIndex: descriptor.orderIndex, exerciseName: descriptor.name)

            if unitsByGroupID[groupID] == nil {
                unitsByGroupID[groupID] = descriptor.weightUnit
            }
        }

        return unitsByGroupID
    }

    private static func exerciseGroupID(orderIndex: Int, exerciseName: String) -> String {
        "\(orderIndex)-\(exerciseName)"
    }

    private static func areSetsInDisplayOrder(_ lhs: WorkoutSet, _ rhs: WorkoutSet) -> Bool {
        if lhs.exerciseOrderIndex != rhs.exerciseOrderIndex {
            return lhs.exerciseOrderIndex < rhs.exerciseOrderIndex
        }

        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt < rhs.completedAt
        }

        if lhs.setIndex != rhs.setIndex {
            return lhs.setIndex < rhs.setIndex
        }

        return (lhs.side?.rawValue ?? "") < (rhs.side?.rawValue ?? "")
    }
}

enum WorkoutHistoryDisplay {
    static func listTitle(
        for summary: WorkoutHistorySessionSummary,
        showsStartTime: Bool,
        now: Date
    ) -> String {
        let dateText = dateText(for: summary.startedAt, timeZoneIdentifier: summary.timezoneIdentifier)
        let timeText = showsStartTime ? " \(timeText(for: summary.startedAt, timeZoneIdentifier: summary.timezoneIdentifier))" : ""
        let statusText = summary.endedAt == nil ? " (进行中)" : ""
        let durationText = durationText(from: summary.startedAt, to: summary.endedAt ?? now)

        return "\(dateText)\(timeText) · \(summary.templateName)\(statusText) · \(summary.setCount)组 · \(durationText)"
    }

    static func fullDateTimeText(for date: Date, timeZoneIdentifier: String) -> String {
        format(date, timeZoneIdentifier: timeZoneIdentifier, dateFormat: "yyyy-MM-dd HH:mm")
    }

    static func timeText(for date: Date, timeZoneIdentifier: String?) -> String {
        format(date, timeZoneIdentifier: timeZoneIdentifier, dateFormat: "HH:mm")
    }

    static func weightText(_ value: Double) -> String {
        WeightDisplay.text(value)
    }

    static func setValueText(weightKilograms: Double, reps: Int, unit: WeightUnit) -> String {
        "\(WeightDisplay.text(forKilograms: weightKilograms, unit: unit)) \(unit.label) x \(reps)"
    }

    static func sideText(_ side: Side) -> String {
        switch side {
        case .left:
            return "左"
        case .right:
            return "右"
        }
    }

    private static func dateText(for date: Date, timeZoneIdentifier: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayIndex = max(1, min(7, calendar.component(.weekday, from: date))) - 1
        let dayText = format(date, timeZoneIdentifier: timeZoneIdentifier, dateFormat: "yyyy-MM-dd")

        return "\(dayText) (\(weekdaySymbols[weekdayIndex]))"
    }

    private static func durationText(from startDate: Date, to endDate: Date) -> String {
        let elapsedMinutes = max(0, Int(endDate.timeIntervalSince(startDate)) / 60)
        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private static func format(_ date: Date, timeZoneIdentifier: String?, dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = dateFormat

        return formatter.string(from: date)
    }
}
