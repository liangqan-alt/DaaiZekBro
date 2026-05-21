import Foundation
import SwiftData

enum CSVExporterError: Error, LocalizedError, Equatable {
    case invalidTimeZoneIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .invalidTimeZoneIdentifier(let identifier):
            "训练记录的时区无效：\(identifier)"
        }
    }
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
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.startedAt)]
            )
        )
        let allSets = try context.fetch(FetchDescriptor<WorkoutSet>())
        var lines = [csvLine(columnNames)]

        for session in sessions {
            let sessionSets = sortedSets(allSets.filter { $0.session?.id == session.id })

            guard sessionSets.isEmpty == false else {
                continue
            }

            guard let timeZone = TimeZone(identifier: session.timezoneIdentifier) else {
                throw CSVExporterError.invalidTimeZoneIdentifier(session.timezoneIdentifier)
            }

            for set in sessionSets {
                lines.append(csvLine(fields(for: set, in: session, timeZone: timeZone)))
            }
        }

        return lines.joined(separator: "\n") + "\n"
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

    private static func fileName(exportedAt: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return "gym_log_\(formatter.string(from: exportedAt)).csv"
    }
}
