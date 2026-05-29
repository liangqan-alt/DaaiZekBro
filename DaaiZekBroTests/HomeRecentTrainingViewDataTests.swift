import Foundation
import Testing
@testable import DaaiZekBro

struct HomeRecentTrainingViewDataTests {
    @Test func rowsIncludeOnlyEndedSessionsWithSets() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)
        let now = try date(2026, 5, 22, 12, 0, 0, timeZone: timeZone)
        let validSession = session(
            name: "Push A",
            startedAt: try date(2026, 5, 21, 9, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 21, 10, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let endedEmptySession = session(
            name: "Pull A",
            startedAt: try date(2026, 5, 20, 9, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 20, 10, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let openSessionWithSet = session(
            name: "Legs A",
            startedAt: try date(2026, 5, 22, 9, 0, 0, timeZone: timeZone),
            endedAt: nil,
            timeZone: timeZone
        )
        let sets = [
            WorkoutSet(session: validSession, exerciseNameSnapshot: "固定器械卧推"),
            WorkoutSet(session: openSessionWithSet, exerciseNameSnapshot: "腿举机"),
        ]

        let rows = HomeRecentTrainingViewData.rows(
            sessions: [validSession, endedEmptySession, openSessionWithSet],
            sets: sets,
            now: now,
            calendar: calendar
        )

        #expect(rows.map(\.id) == [validSession.id])
    }

    @Test func rowsReturnLatestThreeValidCompletedSessionsByStartTime() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)
        let now = try date(2026, 5, 22, 12, 0, 0, timeZone: timeZone)
        let oldest = completedSession(
            name: "Oldest",
            startedAt: try date(2026, 5, 18, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let third = completedSession(
            name: "Third",
            startedAt: try date(2026, 5, 19, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let second = completedSession(
            name: "Second",
            startedAt: try date(2026, 5, 20, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let latest = completedSession(
            name: "Latest",
            startedAt: try date(2026, 5, 21, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let endedEmptyNewer = session(
            name: "Ended Empty",
            startedAt: try date(2026, 5, 22, 8, 0, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 22, 9, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let openNewerWithSet = session(
            name: "Open Newer",
            startedAt: try date(2026, 5, 22, 10, 0, 0, timeZone: timeZone),
            endedAt: nil,
            timeZone: timeZone
        )
        let validSessions = [oldest, third, second, latest]
        let sessions = validSessions + [endedEmptyNewer, openNewerWithSet]
        let sets = validSessions.map { WorkoutSet(session: $0, exerciseNameSnapshot: "动作") }
            + [WorkoutSet(session: openNewerWithSet, exerciseNameSnapshot: "动作")]

        let rows = HomeRecentTrainingViewData.rows(
            sessions: sessions,
            sets: sets,
            now: now,
            calendar: calendar
        )

        #expect(rows.map(\.id) == [latest.id, second.id, third.id])
        #expect(rows.contains { $0.id == oldest.id } == false)
        #expect(rows.contains { $0.id == endedEmptyNewer.id } == false)
        #expect(rows.contains { $0.id == openNewerWithSet.id } == false)
    }

    @Test func rowsSortByStartedAtAcrossTimeZoneMonthBoundaries() throws {
        let tokyo = try requiredTimeZone("Asia/Tokyo")
        let losAngeles = try requiredTimeZone("America/Los_Angeles")
        let calendar = gregorianCalendar(timeZone: tokyo)
        let now = try date(2026, 1, 1, 12, 0, 0, timeZone: tokyo)
        let olderButJanuaryLocal = session(
            name: "Older January Local",
            startedAt: try date(2026, 1, 1, 8, 30, 0, timeZone: tokyo),
            endedAt: try date(2026, 1, 1, 9, 0, 0, timeZone: tokyo),
            timeZone: tokyo
        )
        let newerButDecemberLocal = session(
            name: "Newer December Local",
            startedAt: try date(2025, 12, 31, 16, 30, 0, timeZone: losAngeles),
            endedAt: try date(2025, 12, 31, 17, 0, 0, timeZone: losAngeles),
            timeZone: losAngeles
        )
        let sets = [
            WorkoutSet(session: olderButJanuaryLocal, exerciseNameSnapshot: "动作"),
            WorkoutSet(session: newerButDecemberLocal, exerciseNameSnapshot: "动作"),
        ]

        let rows = HomeRecentTrainingViewData.rows(
            sessions: [olderButJanuaryLocal, newerButDecemberLocal],
            sets: sets,
            now: now,
            calendar: calendar
        )

        #expect(rows.map(\.id) == [newerButDecemberLocal.id, olderButJanuaryLocal.id])
    }

    private func completedSession(
        name: String,
        startedAt: Date,
        timeZone: TimeZone
    ) -> WorkoutSession {
        session(
            name: name,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            timeZone: timeZone
        )
    }

    private func session(
        name: String,
        startedAt: Date,
        endedAt: Date?,
        timeZone: TimeZone
    ) -> WorkoutSession {
        WorkoutSession(
            id: UUID(),
            templateNameSnapshot: name,
            startedAt: startedAt,
            endedAt: endedAt,
            timezoneIdentifier: timeZone.identifier
        )
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
            throw HomeRecentTrainingViewDataTestError.invalidDate
        }

        return date
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw HomeRecentTrainingViewDataTestError.missingTimeZone(identifier)
        }

        return timeZone
    }

    private func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar
    }
}

private enum HomeRecentTrainingViewDataTestError: Error {
    case invalidDate
    case missingTimeZone(String)
}
