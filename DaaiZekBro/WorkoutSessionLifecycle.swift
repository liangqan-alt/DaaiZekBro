import Foundation
import SwiftData

enum WorkoutSessionLifecycleError: Error, LocalizedError, Equatable {
    case openSessionAlreadyExists

    var errorDescription: String? {
        switch self {
        case .openSessionAlreadyExists:
            "已有未结束的训练"
        }
    }
}

@MainActor
enum WorkoutSessionLifecycle {
    static func currentOpenSession(in context: ModelContext) throws -> WorkoutSession? {
        let sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.startedAt, order: .reverse)]
            )
        )

        return sessions.first { $0.endedAt == nil }
    }

    static func createSession(
        for template: Template,
        in context: ModelContext,
        startedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> WorkoutSession {
        guard try currentOpenSession(in: context) == nil else {
            throw WorkoutSessionLifecycleError.openSessionAlreadyExists
        }

        let session = WorkoutSession(
            template: template,
            templateNameSnapshot: template.name,
            startedAt: startedAt,
            timezoneIdentifier: timeZone.identifier
        )

        context.insert(session)
        try context.save()

        return session
    }

    static func end(
        _ session: WorkoutSession,
        in context: ModelContext,
        endedAt: Date = Date()
    ) throws {
        session.endedAt = endedAt
        try context.save()
    }

    static func discard(_ session: WorkoutSession, in context: ModelContext) throws {
        let sessionID = session.id
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())

        for set in sets where set.session?.id == sessionID {
            context.delete(set)
        }

        context.delete(session)
        try context.save()
    }

    static func resolvedTemplate(for session: WorkoutSession, in context: ModelContext) throws -> Template? {
        if let template = session.template {
            return template
        }

        let templates = try context.fetch(FetchDescriptor<Template>())

        return templates.first { $0.name == session.templateNameSnapshot }
    }

    static func exercises(for session: WorkoutSession, in context: ModelContext) throws -> [Exercise] {
        guard let template = try resolvedTemplate(for: session, in: context) else {
            return []
        }

        return orderedExercises(for: template)
    }

    static func orderedExercises(for template: Template) -> [Exercise] {
        guard let seedTemplate = SeedData.templateExerciseNames.first(where: { $0.name == template.name }) else {
            return template.exercises
        }

        let exercisesByName = Dictionary(uniqueKeysWithValues: template.exercises.map { ($0.name, $0) })

        return seedTemplate.exerciseNames.compactMap { exercisesByName[$0] }
    }

    static func recordedSetCountsByExerciseName(
        for session: WorkoutSession,
        in context: ModelContext
    ) throws -> [String: Int] {
        let sessionID = session.id
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        var counts: [String: Int] = [:]

        for set in sets where set.session?.id == sessionID {
            let exerciseName = set.exerciseNameSnapshot.isEmpty ? set.exercise?.name : set.exerciseNameSnapshot

            guard let exerciseName, exerciseName.isEmpty == false else {
                continue
            }

            counts[exerciseName, default: 0] += 1
        }

        return counts
    }
}
