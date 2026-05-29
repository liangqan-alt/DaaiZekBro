import Foundation
import Testing
@testable import DaaiZekBro

struct WorkoutHistoryTests {
    @Test func historySectionsHideEmptySessionsAndFormatMonthRows() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)
        let now = try date(2026, 5, 22, 12, 0, 0, timeZone: timeZone)
        let emptySession = WorkoutSession(
            id: UUID(),
            templateNameSnapshot: "Pull A",
            startedAt: try date(2026, 5, 20, 7, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 20, 7, 30, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier
        )
        let morningSession = WorkoutSession(
            id: UUID(),
            templateNameSnapshot: "Push A",
            startedAt: try date(2026, 5, 20, 9, 30, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 20, 10, 42, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier
        )
        let eveningSession = WorkoutSession(
            id: UUID(),
            templateNameSnapshot: "Pull A",
            startedAt: try date(2026, 5, 20, 18, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 20, 18, 30, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier
        )
        let aprilSession = WorkoutSession(
            id: UUID(),
            templateNameSnapshot: "Legs A",
            startedAt: try date(2026, 4, 30, 8, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 4, 30, 8, 45, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier
        )
        let sets = [
            WorkoutSet(session: morningSession, exerciseNameSnapshot: "固定器械卧推"),
            WorkoutSet(session: eveningSession, exerciseNameSnapshot: "高位下拉"),
            WorkoutSet(session: aprilSession, exerciseNameSnapshot: "腿举机"),
        ]

        let sections = WorkoutHistoryData.sections(
            sessions: [emptySession, morningSession, eveningSession, aprilSession],
            sets: sets,
            now: now,
            calendar: calendar
        )

        #expect(sections.map(\.title) == ["2026 年 5 月", "2026 年 4 月"])
        #expect(sections[0].rows.map(\.id) == [eveningSession.id, morningSession.id])
        #expect(sections[0].rows.map(\.title) == [
            "2026-05-20 (三) 18:00 · Pull A · 1组 · 30m",
            "2026-05-20 (三) 09:30 · Push A · 1组 · 1h 12m",
        ])
        #expect(sections[1].rows[0].title == "2026-04-30 (四) · Legs A · 1组 · 45m")
        #expect(sections.flatMap(\.rows).contains { $0.id == emptySession.id } == false)
    }

    @Test func ongoingSessionTitleShowsStatusAndUsesNowForDuration() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let startedAt = try date(2026, 5, 22, 9, 0, 0, timeZone: timeZone)
        let summary = WorkoutHistorySessionSummary(
            id: UUID(),
            templateName: "Push A",
            startedAt: startedAt,
            endedAt: nil,
            timezoneIdentifier: timeZone.identifier,
            setCount: 2
        )

        let title = WorkoutHistoryDisplay.listTitle(
            for: summary,
            showsStartTime: false,
            now: try date(2026, 5, 22, 10, 0, 0, timeZone: timeZone)
        )

        #expect(title == "2026-05-22 (五) · Push A (进行中) · 2组 · 1h 0m")
    }

    @Test func completedHistoryUsesTemplateNameSnapshotAfterTemplateRename() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let template = Template(name: "Push A")
        let session = WorkoutSession(
            id: UUID(),
            template: template,
            templateNameSnapshot: "Push A",
            startedAt: try date(2026, 5, 22, 9, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 22, 10, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier
        )
        let set = WorkoutSet(session: session, exerciseNameSnapshot: "固定器械卧推")

        template.name = "Push Prime"

        let summaries = WorkoutHistoryData.summaries(sessions: [session], sets: [set])

        #expect(WorkoutHistoryData.templateName(for: session) == "Push A")
        #expect(summaries.map(\.templateName) == ["Push A"])
    }

    @Test func completedHistoryUsesTemplateNameSnapshotAfterTemplateDeletion() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let template = Template(name: "Push A")
        let session = WorkoutSession(
            id: UUID(),
            template: template,
            templateNameSnapshot: "Push A",
            startedAt: try date(2026, 5, 22, 9, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 22, 10, 0, 0, timeZone: timeZone),
            timezoneIdentifier: timeZone.identifier
        )

        session.template = nil

        #expect(WorkoutHistoryData.templateName(for: session) == "Push A")
    }

    @Test func exerciseGroupsUseSessionSnapshotUnitsWithOldDataFallbacks() {
        let session = WorkoutSession(id: UUID(), templateNameSnapshot: "Mixed Units")
        let kilogramsExercise = Exercise(name: "Leg Press", weightUnit: .kilograms)
        let poundsExercise = Exercise(name: "Chest Press", weightUnit: .pounds)
        let sets = [
            WorkoutSet(
                session: session,
                exercise: kilogramsExercise,
                exerciseNameSnapshot: "Leg Press",
                exerciseOrderIndex: 0,
                weight: 100,
                reps: 8
            ),
            WorkoutSet(
                session: session,
                exercise: poundsExercise,
                exerciseNameSnapshot: "Chest Press",
                exerciseOrderIndex: 1,
                weight: 45.3592,
                reps: 10
            ),
            WorkoutSet(
                session: session,
                exercise: poundsExercise,
                exerciseNameSnapshot: "Old Linked Row",
                exerciseOrderIndex: 2,
                weight: 22.6796,
                reps: 12
            ),
            WorkoutSet(
                session: session,
                exerciseNameSnapshot: "Old Snapshot Only",
                exerciseOrderIndex: 3,
                weight: 30,
                reps: 15
            ),
        ]
        let descriptors = [
            WorkoutSessionExerciseDescriptor(
                exercise: kilogramsExercise,
                name: "Leg Press",
                defaultRestSeconds: 90,
                isUnilateral: false,
                weightUnit: .kilograms,
                orderIndex: 0
            ),
            WorkoutSessionExerciseDescriptor(
                exercise: poundsExercise,
                name: "Chest Press",
                defaultRestSeconds: 90,
                isUnilateral: false,
                weightUnit: .pounds,
                orderIndex: 1
            ),
        ]

        let groups = WorkoutHistoryData.exerciseGroups(
            for: session.id,
            sets: sets,
            exerciseDescriptors: descriptors
        )

        #expect(groups.map(\.exerciseName) == [
            "Leg Press",
            "Chest Press",
            "Old Linked Row",
            "Old Snapshot Only",
        ])
        #expect(groups.map(\.weightUnit) == [.kilograms, .pounds, .pounds, .kilograms])
        #expect(WorkoutHistoryDisplay.setValueText(
            weightKilograms: groups[0].sets[0].weight,
            reps: groups[0].sets[0].reps,
            unit: groups[0].weightUnit
        ) == "100 kg x 8")
        #expect(WorkoutHistoryDisplay.setValueText(
            weightKilograms: groups[1].sets[0].weight,
            reps: groups[1].sets[0].reps,
            unit: groups[1].weightUnit
        ) == "100 lb x 10")
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
            throw WorkoutHistoryTestError.invalidDate
        }

        return date
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw WorkoutHistoryTestError.missingTimeZone(identifier)
        }

        return timeZone
    }

    private func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar
    }
}

private enum WorkoutHistoryTestError: Error {
    case invalidDate
    case missingTimeZone(String)
}
