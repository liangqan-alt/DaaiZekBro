import Foundation
import SwiftData

@MainActor
enum WorkoutStartFlow {
    enum StartResult {
        case started(WorkoutSession)
        case conflict(WorkoutSession)
    }

    static func startOrConflict(
        for template: Template,
        in context: ModelContext,
        startedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> StartResult {
        if let openSession = try WorkoutSessionLifecycle.currentOpenSession(in: context) {
            return .conflict(openSession)
        }

        let session = try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: startedAt,
            timeZone: timeZone
        )

        return .started(session)
    }
}
