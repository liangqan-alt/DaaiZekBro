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

    @Test func setValueTextFormatsKilograms() {
        let text = WorkoutHistoryDisplay.setValueText(weightKilograms: 45.4, reps: 8, unit: .kilograms)

        #expect(text == "45.4 kg x 8")
    }

    @Test func setValueTextConvertsKilogramsToPounds() {
        let kilograms = WeightUnit.pounds.kilograms(fromDisplayValue: 100)
        let text = WorkoutHistoryDisplay.setValueText(weightKilograms: kilograms, reps: 8, unit: .pounds)

        #expect(text == "100 lb x 8")
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
