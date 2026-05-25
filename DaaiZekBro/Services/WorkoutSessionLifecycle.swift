import Foundation
import SwiftData

enum WorkoutSessionLifecycleError: Error, LocalizedError, Equatable {
    case openSessionAlreadyExists
    case cannotDeleteOpenSession

    var errorDescription: String? {
        switch self {
        case .openSessionAlreadyExists:
            "已有未结束的训练"
        case .cannotDeleteOpenSession:
            "进行中的训练请先结束或丢弃后再删除"
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
            templateStableIDSnapshot: template.stableID,
            startedAt: startedAt,
            timezoneIdentifier: timeZone.identifier
        )
        let exerciseDescriptors = try exerciseDescriptors(for: template, in: context)

        context.insert(session)

        for descriptor in exerciseDescriptors {
            context.insert(
                WorkoutSessionExerciseSnapshot(
                    session: session,
                    exercise: descriptor.exercise,
                    exerciseNameSnapshot: descriptor.name,
                    defaultRestSecondsSnapshot: descriptor.defaultRestSeconds,
                    isUnilateralSnapshot: descriptor.isUnilateral,
                    orderIndex: descriptor.orderIndex
                )
            )
        }

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

    static func deleteCompletedSessions(sessionIDs: Set<UUID>, in context: ModelContext) throws {
        guard sessionIDs.isEmpty == false else {
            return
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { sessionIDs.contains($0.id) }

        guard sessions.allSatisfy({ $0.endedAt != nil }) else {
            throw WorkoutSessionLifecycleError.cannotDeleteOpenSession
        }

        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())

        for set in sets where set.session.map({ sessionIDs.contains($0.id) }) == true {
            context.delete(set)
        }

        for session in sessions {
            context.delete(session)
        }

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
        try exerciseDescriptors(for: session, in: context).compactMap(\.exercise)
    }

    static func exerciseDescriptor(
        named exerciseName: String,
        for session: WorkoutSession,
        in context: ModelContext
    ) throws -> WorkoutSessionExerciseDescriptor? {
        try exerciseDescriptors(for: session, in: context).first { $0.name == exerciseName }
    }

    static func exerciseDescriptors(
        for session: WorkoutSession,
        in context: ModelContext
    ) throws -> [WorkoutSessionExerciseDescriptor] {
        let snapshots = try context.fetch(FetchDescriptor<WorkoutSessionExerciseSnapshot>())
            .filter { $0.session?.id == session.id }

        if snapshots.isEmpty == false {
            return snapshots
                .sorted(by: snapshotSort)
                .map { snapshot in
                    WorkoutSessionExerciseDescriptor(
                        exercise: snapshot.exercise,
                        name: snapshot.exerciseNameSnapshot,
                        defaultRestSeconds: snapshot.defaultRestSecondsSnapshot,
                        isUnilateral: snapshot.isUnilateralSnapshot,
                        orderIndex: snapshot.orderIndex
                    )
                }
        }

        guard let template = try resolvedTemplate(for: session, in: context) else {
            return []
        }

        return try exerciseDescriptors(for: template, in: context)
    }

    static func exerciseDescriptors(
        for template: Template,
        in context: ModelContext
    ) throws -> [WorkoutSessionExerciseDescriptor] {
        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { $0.template === template }

        let orderedExerciseDescriptors: [(exercise: Exercise, orderIndex: Int)]

        if templateExercises.isEmpty {
            orderedExerciseDescriptors = orderedExercises(for: template).enumerated().map { index, exercise in
                (exercise: exercise, orderIndex: index)
            }
        } else {
            orderedExerciseDescriptors = templateExercises
                .sorted(by: templateExerciseSort)
                .compactMap { templateExercise in
                    guard let exercise = templateExercise.exercise else { return nil }

                    return (exercise: exercise, orderIndex: templateExercise.orderIndex)
                }
        }

        return orderedExerciseDescriptors.map { exercise, orderIndex in
            WorkoutSessionExerciseDescriptor(
                exercise: exercise,
                name: exercise.name,
                defaultRestSeconds: exercise.defaultRestSeconds,
                isUnilateral: exercise.isUnilateral,
                orderIndex: orderIndex
            )
        }
    }

    static func orderedExercises(for template: Template) -> [Exercise] {
        let linkedExercises = template.templateExercises
            .sorted(by: templateExerciseSort)
            .compactMap(\.exercise)

        if linkedExercises.isEmpty == false {
            return linkedExercises
        }

        guard let seedTemplate = SeedData.templateExerciseNames.first(where: { $0.name == template.name }) else {
            return template.exercises
        }

        let exercisesByName = Dictionary(uniqueKeysWithValues: template.exercises.map { ($0.name, $0) })

        return seedTemplate.exerciseNames.compactMap { exercisesByName[$0] }
    }

    private static func snapshotSort(
        _ lhs: WorkoutSessionExerciseSnapshot,
        _ rhs: WorkoutSessionExerciseSnapshot
    ) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }

        return lhs.exerciseNameSnapshot < rhs.exerciseNameSnapshot
    }

    private static func templateExerciseSort(_ lhs: TemplateExercise, _ rhs: TemplateExercise) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }

        return (lhs.exercise?.name ?? "") < (rhs.exercise?.name ?? "")
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
