import Foundation
import SwiftData

enum CSVExporterError: Error, LocalizedError, Equatable {
    case invalidTimeZoneIdentifier(String)
    case invalidDateRange
    case noDataInRange

    var errorDescription: String? {
        switch self {
        case .invalidTimeZoneIdentifier(let identifier):
            "训练记录的时区无效：\(identifier)"
        case .invalidDateRange:
            "结束日期不能早于起始日期"
        case .noDataInRange:
            "该时间范围内暂无训练"
        }
    }
}

enum CSVExportRange: Equatable {
    case full
    case last7Days
    case last30Days
    case custom(startDate: Date, endDate: Date)

    func resolved(now: Date = Date(), calendar: Calendar = .current) throws -> CSVResolvedExportRange {
        switch self {
        case .full:
            return .full
        case .last7Days:
            return try resolvedRecentRange(dayCount: 7, now: now, calendar: calendar)
        case .last30Days:
            return try resolvedRecentRange(dayCount: 30, now: now, calendar: calendar)
        case .custom(let startDate, let endDate):
            return try resolvedCustomRange(startDate: startDate, endDate: endDate, calendar: calendar)
        }
    }

    private func resolvedRecentRange(
        dayCount: Int,
        now: Date,
        calendar: Calendar
    ) throws -> CSVResolvedExportRange {
        let endDay = calendar.startOfDay(for: now)

        guard let startDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: endDay),
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else {
            throw CSVExporterError.invalidDateRange
        }

        return .bounded(startDate: startDay, endDate: endDay, endExclusive: endExclusive)
    }

    private func resolvedCustomRange(
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) throws -> CSVResolvedExportRange {
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        guard startDay <= endDay,
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else {
            throw CSVExporterError.invalidDateRange
        }

        return .bounded(startDate: startDay, endDate: endDay, endExclusive: endExclusive)
    }
}

struct CSVResolvedExportRange: Equatable {
    let startDate: Date?
    let endDate: Date?
    let endExclusive: Date?

    static let full = CSVResolvedExportRange(startDate: nil, endDate: nil, endExclusive: nil)

    static func bounded(startDate: Date, endDate: Date, endExclusive: Date) -> CSVResolvedExportRange {
        CSVResolvedExportRange(startDate: startDate, endDate: endDate, endExclusive: endExclusive)
    }

    var isFull: Bool {
        startDate == nil
    }

    func contains(_ date: Date) -> Bool {
        guard let startDate, let endExclusive else {
            return true
        }

        return date >= startDate && date < endExclusive
    }
}

struct CSVExportSummary: Equatable {
    let sessionCount: Int
    let setCount: Int
}

@MainActor
final class CSVExporter {
    static let columnNames = [
        "schema_version",
        "session_id",
        "session_started_at",
        "session_ended_at",
        "timezone",
        "template_name",
        "exercise_order",
        "exercise_name",
        "set_index",
        "weight_kg",
        "reps",
        "rpe",
        "side",
        "completed_at",
        "volume_kg_rep",
        "e1rm_epley_kg",
    ]

    private static let schemaVersion = "1.0"
    private static let byteOrderMark = "\u{FEFF}"

    static func csvString(in context: ModelContext) throws -> String {
        try csvString(in: context, resolvedRange: .full)
    }

    static func csvString(
        in context: ModelContext,
        range: CSVExportRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> String {
        try csvString(in: context, resolvedRange: try range.resolved(now: now, calendar: calendar))
    }

    static func csvString(in context: ModelContext, sessionIDs: Set<UUID>) throws -> String {
        try csvString(from: exportRows(in: context, sessionIDs: sessionIDs))
    }

    static func summary(
        in context: ModelContext,
        range: CSVExportRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> CSVExportSummary {
        let resolvedRange = try range.resolved(now: now, calendar: calendar)
        let rows = try exportRows(in: context, resolvedRange: resolvedRange)
        let sessionIDs = Set(rows.map { $0.session.id })

        return CSVExportSummary(sessionCount: sessionIDs.count, setCount: rows.count)
    }

    static func exportFile(
        in context: ModelContext,
        range: CSVExportRange,
        exportedAt: Date = Date(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) throws -> URL {
        let resolvedRange = try range.resolved(now: exportedAt, calendar: calendar)
        let rows = try exportRows(in: context, resolvedRange: resolvedRange)

        guard rows.isEmpty == false else {
            throw CSVExporterError.noDataInRange
        }

        let fileURL = fileManager.temporaryDirectory
            .appendingPathComponent(fileName(for: resolvedRange, exportedAt: exportedAt, calendar: calendar))
        let csvData = Data((byteOrderMark + csvString(from: rows)).utf8)

        try csvData.write(to: fileURL, options: .atomic)

        return fileURL
    }

    static func exportFile(
        in context: ModelContext,
        sessionIDs: Set<UUID>,
        exportedAt: Date = Date(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) throws -> URL {
        let rows = try exportRows(in: context, sessionIDs: sessionIDs)

        guard rows.isEmpty == false else {
            throw CSVExporterError.noDataInRange
        }

        let fileURL = fileManager.temporaryDirectory
            .appendingPathComponent(selectedFileName(exportedAt: exportedAt, calendar: calendar))
        let csvData = Data((byteOrderMark + csvString(from: rows)).utf8)

        try csvData.write(to: fileURL, options: .atomic)

        return fileURL
    }

    private static func csvString(in context: ModelContext, resolvedRange: CSVResolvedExportRange) throws -> String {
        try csvString(from: exportRows(in: context, resolvedRange: resolvedRange))
    }

    private static func csvString(from rows: [CSVExportRow]) -> String {
        var lines = [csvLine(columnNames)]

        for row in rows {
            lines.append(csvLine(fields(for: row.set, in: row.session, timeZone: row.timeZone)))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func exportRows(
        in context: ModelContext,
        resolvedRange: CSVResolvedExportRange
    ) throws -> [CSVExportRow] {
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.startedAt)]
            )
        )
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        var rows: [CSVExportRow] = []

        for session in sessions {
            let sessionSets = sortedSets(
                allSets.filter { set in
                    set.session?.id == session.id && resolvedRange.contains(set.completedAt)
                }
            )

            guard sessionSets.isEmpty == false else {
                continue
            }

            guard let timeZone = TimeZone(identifier: session.timezoneIdentifier) else {
                throw CSVExporterError.invalidTimeZoneIdentifier(session.timezoneIdentifier)
            }

            rows.append(contentsOf: sessionSets.map { CSVExportRow(session: session, set: $0, timeZone: timeZone) })
        }

        return rows
    }

    private static func exportRows(
        in context: ModelContext,
        sessionIDs: Set<UUID>
    ) throws -> [CSVExportRow] {
        guard sessionIDs.isEmpty == false else {
            return []
        }

        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.startedAt)]
            )
        )
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        var rows: [CSVExportRow] = []

        for session in sessions where sessionIDs.contains(session.id) {
            let sessionSets = sortedSets(
                allSets.filter { set in
                    set.session?.id == session.id
                }
            )

            guard sessionSets.isEmpty == false else {
                continue
            }

            guard let timeZone = TimeZone(identifier: session.timezoneIdentifier) else {
                throw CSVExporterError.invalidTimeZoneIdentifier(session.timezoneIdentifier)
            }

            rows.append(contentsOf: sessionSets.map { CSVExportRow(session: session, set: $0, timeZone: timeZone) })
        }

        return rows
    }

    static func exportFile(
        in context: ModelContext,
        exportedAt: Date = Date(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) throws -> URL {
        let fileURL = fileManager.temporaryDirectory
            .appendingPathComponent(fileName(exportedAt: exportedAt, calendar: calendar))
        let csvData = Data((byteOrderMark + (try csvString(in: context))).utf8)

        try csvData.write(to: fileURL, options: .atomic)

        return fileURL
    }

    static func fileName(
        for range: CSVExportRange,
        exportedAt: Date = Date(),
        calendar: Calendar = .current
    ) throws -> String {
        try fileName(for: range.resolved(now: exportedAt, calendar: calendar), exportedAt: exportedAt, calendar: calendar)
    }

    private static func fields(
        for set: WorkoutSet,
        in session: WorkoutSession,
        timeZone: TimeZone
    ) -> [String] {
        [
            schemaVersion,
            session.id.uuidString,
            formatDate(session.startedAt, timeZone: timeZone),
            session.endedAt.map { formatDate($0, timeZone: timeZone) } ?? "",
            session.timezoneIdentifier,
            templateName(for: session),
            "\(set.exerciseOrderIndex)",
            exerciseName(for: set),
            "\(set.setIndex)",
            formatWeight(set.weight),
            "\(set.reps)",
            set.rpe.map { "\($0)" } ?? "",
            set.side?.rawValue ?? "",
            formatDate(set.completedAt, timeZone: timeZone),
            formatDerivedValue(set.weight * Double(set.reps)),
            formatDerivedValue(set.weight * (1 + Double(set.reps) / 30)),
        ]
    }

    private static func sortedSets(_ sets: [WorkoutSet]) -> [WorkoutSet] {
        sets.sorted { lhs, rhs in
            if lhs.completedAt != rhs.completedAt {
                return lhs.completedAt < rhs.completedAt
            }

            if lhs.exerciseOrderIndex != rhs.exerciseOrderIndex {
                return lhs.exerciseOrderIndex < rhs.exerciseOrderIndex
            }

            if lhs.setIndex != rhs.setIndex {
                return lhs.setIndex < rhs.setIndex
            }

            return (lhs.side?.rawValue ?? "") < (rhs.side?.rawValue ?? "")
        }
    }

    private static func templateName(for session: WorkoutSession) -> String {
        if session.templateNameSnapshot.isEmpty == false {
            return session.templateNameSnapshot
        }

        return session.template?.name ?? ""
    }

    private static func exerciseName(for set: WorkoutSet) -> String {
        if set.exerciseNameSnapshot.isEmpty == false {
            return set.exerciseNameSnapshot
        }

        return set.exercise?.name ?? ""
    }

    private static func csvLine(_ fields: [String]) -> String {
        fields.map(escapedField).joined(separator: ",")
    }

    private static func escapedField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }

        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func formatDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"

        return formatter.string(from: date)
    }

    private static func formatWeight(_ value: Double) -> String {
        formatNumber(value, minimumFractionDigits: 1, maximumFractionDigits: 1)
    }

    private static func formatDerivedValue(_ value: Double) -> String {
        formatNumber(value, minimumFractionDigits: 1, maximumFractionDigits: 2)
    }

    private static func formatNumber(
        _ value: Double,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func fileName(
        for resolvedRange: CSVResolvedExportRange,
        exportedAt: Date,
        calendar: Calendar
    ) -> String {
        if resolvedRange.isFull {
            return "gym_log_full_\(formatFileDate(exportedAt, calendar: calendar)).csv"
        }

        guard let startDate = resolvedRange.startDate, let endDate = resolvedRange.endDate else {
            return "gym_log_full_\(formatFileDate(exportedAt, calendar: calendar)).csv"
        }

        let startText = formatFileDate(startDate, calendar: calendar)
        let endText = formatFileDate(endDate, calendar: calendar)

        if startText == endText {
            return "gym_log_\(startText).csv"
        }

        return "gym_log_\(startText)_to_\(endText).csv"
    }

    private static func fileName(exportedAt: Date, calendar: Calendar) -> String {
        "gym_log_\(formatFileDate(exportedAt, calendar: calendar)).csv"
    }

    private static func selectedFileName(exportedAt: Date, calendar: Calendar) -> String {
        "gym_log_selected_\(formatFileDate(exportedAt, calendar: calendar)).csv"
    }

    private static func formatFileDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(from: date)
    }
}

private struct CSVExportRow {
    let session: WorkoutSession
    let set: WorkoutSet
    let timeZone: TimeZone
}
