import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct CSVExporterTests {
    @Test func csvStringExportsSchemaRowsAndBoundaries() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        try SeedData.writeAndDedup(in: context)

        let emptyTemplate = try template(named: "Pull A", in: context)
        let emptySession = try WorkoutSessionLifecycle.createSession(
            for: emptyTemplate,
            in: context,
            startedAt: try date(2026, 5, 21, 8, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        try WorkoutSessionLifecycle.end(
            emptySession,
            in: context,
            endedAt: try date(2026, 5, 21, 8, 10, 0, timeZone: timeZone)
        )

        let pushTemplate = try template(named: "Push A", in: context)
        let benchPress = try exercise(named: "固定器械卧推", in: context)
        let pushSession = try WorkoutSessionLifecycle.createSession(
            for: pushTemplate,
            in: context,
            startedAt: try date(2026, 5, 21, 9, 30, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        _ = try WorkoutSetLogging.recordSet(
            sessionID: pushSession.id,
            exerciseName: benchPress.name,
            weight: 30,
            reps: 8,
            rpe: 8,
            side: nil,
            completedAt: try date(2026, 5, 21, 9, 32, 15, timeZone: timeZone),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: pushSession.id,
            exerciseName: benchPress.name,
            weight: 22.5,
            reps: 10,
            rpe: nil,
            side: nil,
            completedAt: try date(2026, 5, 21, 9, 34, 50, timeZone: timeZone),
            in: context
        )
        try WorkoutSessionLifecycle.end(
            pushSession,
            in: context,
            endedAt: try date(2026, 5, 21, 10, 45, 0, timeZone: timeZone)
        )

        let legsTemplate = try template(named: "Legs A", in: context)
        let singleLegCurl = try exercise(named: "跪姿单腿腿弯举", in: context)
        let legsSession = try WorkoutSessionLifecycle.createSession(
            for: legsTemplate,
            in: context,
            startedAt: try date(2026, 5, 22, 8, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        _ = try WorkoutSetLogging.recordSet(
            sessionID: legsSession.id,
            exerciseName: singleLegCurl.name,
            weight: 24.9,
            reps: 12,
            rpe: 8,
            side: .left,
            completedAt: try date(2026, 5, 22, 8, 25, 0, timeZone: timeZone),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: legsSession.id,
            exerciseName: singleLegCurl.name,
            weight: 24.9,
            reps: 12,
            rpe: nil,
            side: .right,
            completedAt: try date(2026, 5, 22, 8, 27, 0, timeZone: timeZone),
            in: context
        )

        let records = csvRecords(from: try CSVExporter.csvString(in: context))

        #expect(records.count == 5)
        #expect(records[0] == CSVExporter.columnNames)
        #expect(records.dropFirst().allSatisfy { $0.count == CSVExporter.columnNames.count })

        #expect(records[1] == [
            "1.0",
            pushSession.id.uuidString,
            "2026-05-21T09:30:00+08:00",
            "2026-05-21T10:45:00+08:00",
            "Asia/Shanghai",
            "Push A",
            "\(try seedExerciseOrder(templateName: "Push A", exerciseName: benchPress.name))",
            benchPress.name,
            "1",
            "30.0",
            "8",
            "8",
            "",
            "2026-05-21T09:32:15+08:00",
            "240.0",
            "38.0",
        ])
        #expect(records[2] == [
            "1.0",
            pushSession.id.uuidString,
            "2026-05-21T09:30:00+08:00",
            "2026-05-21T10:45:00+08:00",
            "Asia/Shanghai",
            "Push A",
            "\(try seedExerciseOrder(templateName: "Push A", exerciseName: benchPress.name))",
            benchPress.name,
            "2",
            "22.5",
            "10",
            "",
            "",
            "2026-05-21T09:34:50+08:00",
            "225.0",
            "30.0",
        ])
        #expect(records[3] == [
            "1.0",
            legsSession.id.uuidString,
            "2026-05-22T08:00:00+08:00",
            "",
            "Asia/Shanghai",
            "Legs A",
            "\(try seedExerciseOrder(templateName: "Legs A", exerciseName: singleLegCurl.name))",
            singleLegCurl.name,
            "1",
            "24.9",
            "12",
            "8",
            "left",
            "2026-05-22T08:25:00+08:00",
            "298.8",
            "34.86",
        ])
        #expect(records[4] == [
            "1.0",
            legsSession.id.uuidString,
            "2026-05-22T08:00:00+08:00",
            "",
            "Asia/Shanghai",
            "Legs A",
            "\(try seedExerciseOrder(templateName: "Legs A", exerciseName: singleLegCurl.name))",
            singleLegCurl.name,
            "1",
            "24.9",
            "12",
            "",
            "right",
            "2026-05-22T08:27:00+08:00",
            "298.8",
            "34.86",
        ])
    }

    @Test func csvStringEscapesCommaQuoteAndNewlineFields() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: try date(2026, 5, 21, 9, 30, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        let set = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: try date(2026, 5, 21, 9, 32, 15, timeZone: timeZone),
            in: context
        )

        session.templateNameSnapshot = "Push, \"A\"\n强度"
        set.exerciseNameSnapshot = "卧推, \"重\"\n慢速"
        try context.save()

        let csv = try CSVExporter.csvString(in: context)
        let records = csvRecords(from: csv)

        #expect(csv.contains("\"Push, \"\"A\"\"\n强度\""))
        #expect(csv.contains("\"卧推, \"\"重\"\"\n慢速\""))
        #expect(records[1][5] == "Push, \"A\"\n强度")
        #expect(records[1][7] == "卧推, \"重\"\n慢速")
    }

    @Test func exportFileWritesBOMAndExpectedFileName() throws {
        let context = try makeInMemoryContext()
        let utc = try requiredTimeZone("UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let exportedAt = try date(2026, 5, 21, 12, 0, 0, timeZone: utc)

        let url = try CSVExporter.exportFile(
            in: context,
            exportedAt: exportedAt,
            calendar: calendar
        )
        let data = try Data(contentsOf: url)
        let csvBody = String(data: Data(data.dropFirst(3)), encoding: .utf8)

        #expect(url.lastPathComponent == "gym_log_2026-05-21.csv")
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(csvBody?.hasPrefix(CSVExporter.columnNames.joined(separator: ",")) == true)
    }

    @Test func recentRangesResolveCalendarDayBoundaries() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)
        let now = try date(2026, 5, 21, 15, 0, 0, timeZone: timeZone)

        #expect(try CSVExportRange.last7Days.resolved(now: now, calendar: calendar) == .bounded(
            startDate: try date(2026, 5, 15, 0, 0, 0, timeZone: timeZone),
            endDate: try date(2026, 5, 21, 0, 0, 0, timeZone: timeZone),
            endExclusive: try date(2026, 5, 22, 0, 0, 0, timeZone: timeZone)
        ))
        #expect(try CSVExportRange.last30Days.resolved(now: now, calendar: calendar) == .bounded(
            startDate: try date(2026, 4, 22, 0, 0, 0, timeZone: timeZone),
            endDate: try date(2026, 5, 21, 0, 0, 0, timeZone: timeZone),
            endExclusive: try date(2026, 5, 22, 0, 0, 0, timeZone: timeZone)
        ))
    }

    @Test func rangeFileNamesUseFullSameDayAndMultiDayFormats() throws {
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)
        let exportedAt = try date(2026, 5, 21, 12, 0, 0, timeZone: timeZone)

        #expect(try CSVExporter.fileName(
            for: .full,
            exportedAt: exportedAt,
            calendar: calendar
        ) == "gym_log_full_2026-05-21.csv")
        #expect(try CSVExporter.fileName(
            for: .custom(
                startDate: try date(2026, 5, 21, 9, 0, 0, timeZone: timeZone),
                endDate: try date(2026, 5, 21, 9, 0, 0, timeZone: timeZone)
            ),
            exportedAt: exportedAt,
            calendar: calendar
        ) == "gym_log_2026-05-21.csv")
        #expect(try CSVExporter.fileName(
            for: .custom(
                startDate: try date(2026, 5, 1, 0, 0, 0, timeZone: timeZone),
                endDate: try date(2026, 5, 21, 0, 0, 0, timeZone: timeZone)
            ),
            exportedAt: exportedAt,
            calendar: calendar
        ) == "gym_log_2026-05-01_to_2026-05-21.csv")
    }

    @Test func emptyRangeExportFileThrowsWithoutCreatingFile() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)
        let fileManager = FileManager.default
        let beforeFileNames = try temporaryGymLogFileNames(fileManager: fileManager)

        _ = try recordSession(
            templateName: "Push A",
            exerciseName: "固定器械卧推",
            startedAt: try date(2026, 5, 20, 9, 0, 0, timeZone: timeZone),
            setCompletedAt: try date(2026, 5, 20, 9, 5, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 20, 10, 0, 0, timeZone: timeZone),
            timeZone: timeZone,
            in: context
        )

        var didThrow = false
        do {
            _ = try rangedExportFile(
                in: context,
                range: .custom(
                    startDate: try date(2026, 6, 1, 0, 0, 0, timeZone: timeZone),
                    endDate: try date(2026, 6, 1, 0, 0, 0, timeZone: timeZone)
                ),
                now: try date(2026, 6, 1, 12, 0, 0, timeZone: timeZone),
                exportedAt: try date(2026, 6, 1, 12, 0, 0, timeZone: timeZone),
                fileManager: fileManager,
                calendar: calendar
            )
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(try temporaryGymLogFileNames(fileManager: fileManager) == beforeFileNames)
    }

    @Test func customRangeFiltersCrossMidnightSessionBySetCompletedAt() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)

        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: try date(2026, 5, 20, 23, 50, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: try date(2026, 5, 20, 23, 55, 0, timeZone: timeZone),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: try date(2026, 5, 21, 0, 5, 0, timeZone: timeZone),
            in: context
        )
        try WorkoutSessionLifecycle.end(
            session,
            in: context,
            endedAt: try date(2026, 5, 21, 0, 20, 0, timeZone: timeZone)
        )

        let records = csvRecords(from: try rangedCSVString(
            in: context,
            range: .custom(
                startDate: try date(2026, 5, 21, 0, 0, 0, timeZone: timeZone),
                endDate: try date(2026, 5, 21, 0, 0, 0, timeZone: timeZone)
            ),
            now: try date(2026, 5, 21, 12, 0, 0, timeZone: timeZone),
            calendar: calendar
        ))

        #expect(records.dropFirst().map { $0[13] } == ["2026-05-21T00:05:00+08:00"])
        #expect(records[1][2] == "2026-05-20T23:50:00+08:00")
    }

    @Test func rangeExportIncludesUnfinishedSessionWithBlankEndedAt() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)

        _ = try recordSession(
            templateName: "Push A",
            exerciseName: "固定器械卧推",
            startedAt: try date(2026, 5, 21, 9, 0, 0, timeZone: timeZone),
            setCompletedAt: try date(2026, 5, 21, 9, 5, 0, timeZone: timeZone),
            endedAt: nil,
            timeZone: timeZone,
            in: context
        )

        let records = csvRecords(from: try rangedCSVString(
            in: context,
            range: .last7Days,
            now: try date(2026, 5, 21, 12, 0, 0, timeZone: timeZone),
            calendar: calendar
        ))

        #expect(records[1][3] == "")
    }

    @Test func selectedSessionExportKeepsSchemaUUIDsAndSelectedFileName() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)

        try SeedData.writeAndDedup(in: context)

        let emptyTemplate = try template(named: "Pull A", in: context)
        let emptySession = try WorkoutSessionLifecycle.createSession(
            for: emptyTemplate,
            in: context,
            startedAt: try date(2026, 5, 19, 8, 0, 0, timeZone: timeZone),
            timeZone: timeZone
        )
        try WorkoutSessionLifecycle.end(
            emptySession,
            in: context,
            endedAt: try date(2026, 5, 19, 8, 30, 0, timeZone: timeZone)
        )

        let selectedEndedSession = try recordSession(
            templateName: "Push A",
            exerciseName: "固定器械卧推",
            startedAt: try date(2026, 5, 20, 9, 0, 0, timeZone: timeZone),
            setCompletedAt: try date(2026, 5, 20, 9, 5, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 20, 10, 0, 0, timeZone: timeZone),
            timeZone: timeZone,
            in: context
        )
        let unselectedSession = try recordSession(
            templateName: "Pull A",
            exerciseName: "龙门架宽距高位下拉",
            startedAt: try date(2026, 5, 21, 9, 0, 0, timeZone: timeZone),
            setCompletedAt: try date(2026, 5, 21, 9, 5, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 21, 10, 0, 0, timeZone: timeZone),
            timeZone: timeZone,
            in: context
        )
        let selectedOpenSession = try recordSession(
            templateName: "Push A",
            exerciseName: "固定器械卧推",
            startedAt: try date(2026, 5, 22, 9, 0, 0, timeZone: timeZone),
            setCompletedAt: try date(2026, 5, 22, 9, 5, 0, timeZone: timeZone),
            endedAt: nil,
            timeZone: timeZone,
            in: context
        )
        let selectedSessionIDs = Set([emptySession.id, selectedEndedSession.id, selectedOpenSession.id])

        let records = csvRecords(from: try CSVExporter.csvString(in: context, sessionIDs: selectedSessionIDs))

        #expect(records.count == 3)
        #expect(records[0] == CSVExporter.columnNames)
        #expect(records.dropFirst().allSatisfy { $0.count == CSVExporter.columnNames.count })
        #expect(records.dropFirst().map { $0[1] } == [
            selectedEndedSession.id.uuidString,
            selectedOpenSession.id.uuidString,
        ])
        #expect(records.dropFirst().contains { $0[1] == unselectedSession.id.uuidString } == false)
        #expect(records[2][3] == "")

        let url = try CSVExporter.exportFile(
            in: context,
            sessionIDs: selectedSessionIDs,
            exportedAt: try date(2026, 5, 23, 12, 0, 0, timeZone: timeZone),
            calendar: calendar
        )
        let data = try Data(contentsOf: url)

        #expect(url.lastPathComponent == "gym_log_selected_2026-05-23.csv")
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
    }

    @Test func invalidCustomRangeThrows() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)

        var didThrow = false
        do {
            _ = try rangedCSVString(
                in: context,
                range: .custom(
                    startDate: try date(2026, 5, 22, 0, 0, 0, timeZone: timeZone),
                    endDate: try date(2026, 5, 21, 0, 0, 0, timeZone: timeZone)
                ),
                now: try date(2026, 5, 21, 12, 0, 0, timeZone: timeZone),
                calendar: calendar
            )
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test func exportSummaryCountsMatchCSVRows() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let calendar = gregorianCalendar(timeZone: timeZone)
        let now = try date(2026, 5, 21, 15, 0, 0, timeZone: timeZone)

        _ = try recordSession(
            templateName: "Push A",
            exerciseName: "固定器械卧推",
            startedAt: try date(2026, 5, 21, 9, 0, 0, timeZone: timeZone),
            setCompletedAt: try date(2026, 5, 21, 9, 5, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 21, 10, 0, 0, timeZone: timeZone),
            timeZone: timeZone,
            in: context
        )
        _ = try recordSession(
            templateName: "Legs A",
            exerciseName: "跪姿单腿腿弯举",
            startedAt: try date(2026, 5, 21, 11, 0, 0, timeZone: timeZone),
            setCompletedAt: try date(2026, 5, 21, 11, 5, 0, timeZone: timeZone),
            endedAt: try date(2026, 5, 21, 12, 0, 0, timeZone: timeZone),
            side: .left,
            timeZone: timeZone,
            in: context
        )

        let csv = try rangedCSVString(in: context, range: .last7Days, now: now, calendar: calendar)
        let rows = csvRecords(from: csv).dropFirst()
        let summaryCounts = try rangedSummaryCounts(in: context, range: .last7Days, now: now, calendar: calendar)

        #expect(summaryCounts["rowCount"] == rows.count)
        #expect(summaryCounts["setCount"] == rows.count)
        #expect(summaryCounts["sessionCount"] == Set(rows.map { $0[1] }).count)
    }

    @Test func csvStringThrowsOnInvalidSessionTimeZone() throws {
        let context = try makeInMemoryContext()
        let timeZone = try requiredTimeZone("Asia/Shanghai")

        try SeedData.writeAndDedup(in: context)

        let template = try template(named: "Push A", in: context)
        let exercise = try exercise(named: "固定器械卧推", in: context)
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: try date(2026, 5, 21, 9, 30, 0, timeZone: timeZone),
            timeZone: timeZone
        )

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: try date(2026, 5, 21, 9, 32, 15, timeZone: timeZone),
            in: context
        )

        session.timezoneIdentifier = "Mars/Olympus"
        try context.save()

        var didThrowInvalidTimeZone = false

        do {
            _ = try CSVExporter.csvString(in: context)
        } catch CSVExporterError.invalidTimeZoneIdentifier(let identifier) {
            didThrowInvalidTimeZone = identifier == "Mars/Olympus"
        }

        #expect(didThrowInvalidTimeZone)
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

    private func csvRecords(from csv: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var isQuoted = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let character = csv[index]

            if isQuoted {
                if character == "\"" {
                    let nextIndex = csv.index(after: index)

                    if nextIndex < csv.endIndex, csv[nextIndex] == "\"" {
                        field.append("\"")
                        index = csv.index(after: nextIndex)
                    } else {
                        isQuoted = false
                        index = nextIndex
                    }
                } else {
                    field.append(character)
                    index = csv.index(after: index)
                }

                continue
            }

            switch character {
            case "\"":
                isQuoted = true
            case ",":
                record.append(field)
                field = ""
            case "\n":
                record.append(field)
                records.append(record)
                record = []
                field = ""
            case "\r":
                break
            default:
                field.append(character)
            }

            index = csv.index(after: index)
        }

        if field.isEmpty == false || record.isEmpty == false {
            record.append(field)
            records.append(record)
        }

        return records
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
            throw CSVExporterTestError.invalidDate
        }

        return date
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw CSVExporterTestError.missingTimeZone(identifier)
        }

        return timeZone
    }

    private func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return calendar
    }

    private func recordSession(
        templateName: String,
        exerciseName: String,
        startedAt: Date,
        setCompletedAt: Date,
        endedAt: Date?,
        side: Side? = nil,
        timeZone: TimeZone,
        in context: ModelContext
    ) throws -> WorkoutSession {
        try SeedData.writeAndDedup(in: context)

        let template = try template(named: templateName, in: context)
        let exercise = try exercise(named: exerciseName, in: context)
        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: startedAt,
            timeZone: timeZone
        )

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseName: exercise.name,
            weight: 30,
            reps: 8,
            rpe: nil,
            side: side,
            completedAt: setCompletedAt,
            in: context
        )

        if let endedAt {
            try WorkoutSessionLifecycle.end(session, in: context, endedAt: endedAt)
        }

        return session
    }

    private func temporaryGymLogFileNames(fileManager: FileManager) throws -> Set<String> {
        Set(
            try fileManager
                .contentsOfDirectory(atPath: fileManager.temporaryDirectory.path)
                .filter { $0.hasPrefix("gym_log_") && $0.hasSuffix(".csv") }
        )
    }

    private func rangedCSVString(
        in context: ModelContext,
        range: CSVExportRange,
        now: Date,
        calendar: Calendar
    ) throws -> String {
        try CSVExporter.csvString(in: context, range: range, now: now, calendar: calendar)
    }

    private func rangedExportFile(
        in context: ModelContext,
        range: CSVExportRange,
        now: Date,
        exportedAt: Date,
        fileManager: FileManager = .default,
        calendar: Calendar
    ) throws -> URL {
        _ = now

        return try CSVExporter.exportFile(
            in: context,
            range: range,
            exportedAt: exportedAt,
            fileManager: fileManager,
            calendar: calendar
        )
    }

    private func rangedSummaryCounts(
        in context: ModelContext,
        range: CSVExportRange,
        now: Date,
        calendar: Calendar
    ) throws -> [String: Int] {
        let summary = try CSVExporter.summary(in: context, range: range, now: now, calendar: calendar)

        return [
            "rowCount": summary.setCount,
            "sessionCount": summary.sessionCount,
            "setCount": summary.setCount,
        ]
    }

    private func fetchTemplates(in context: ModelContext) throws -> [Template] {
        try context.fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\Template.name)]))
    }

    private func fetchExercises(in context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\Exercise.name)]))
    }

    private func template(named name: String, in context: ModelContext) throws -> Template {
        guard let template = try fetchTemplates(in: context).first(where: { $0.name == name }) else {
            throw CSVExporterTestError.missingTemplate(name)
        }

        return template
    }

    private func exercise(named name: String, in context: ModelContext) throws -> Exercise {
        guard let exercise = try fetchExercises(in: context).first(where: { $0.name == name }) else {
            throw CSVExporterTestError.missingExercise(name)
        }

        return exercise
    }

    private func seedExerciseOrder(templateName: String, exerciseName: String) throws -> Int {
        guard let seedTemplate = SeedData.templateExerciseNames.first(where: { $0.name == templateName }) else {
            throw CSVExporterTestError.missingTemplate(templateName)
        }

        guard let order = seedTemplate.exerciseNames.firstIndex(of: exerciseName) else {
            throw CSVExporterTestError.missingExercise(exerciseName)
        }

        return order
    }
}

private enum CSVExporterTestError: Error {
    case invalidDate
    case missingExercise(String)
    case missingTemplate(String)
    case missingTimeZone(String)
}
