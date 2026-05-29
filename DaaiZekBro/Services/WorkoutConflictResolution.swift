import Foundation
import SwiftData

@MainActor
enum WorkoutConflictResolution {
    enum Choice {
        case endCurrentAndCreate
        case discardCurrentAndCreate
    }

    struct NotificationCanceller {
        var cancelRestCompletionNotification: @MainActor () -> Void

        static let live = NotificationCanceller {
            UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
        }
    }

    struct Dependencies {
        var currentOpenSession: @MainActor (ModelContext) throws -> WorkoutSession?
        var endSession: @MainActor (WorkoutSession, ModelContext, Date) throws -> Void
        var discardSession: @MainActor (WorkoutSession, ModelContext) throws -> Void
        var createSession: @MainActor (Template, ModelContext, Date, TimeZone) throws -> WorkoutSession

        static let live = Dependencies(
            currentOpenSession: { context in
                try WorkoutSessionLifecycle.currentOpenSession(in: context)
            },
            endSession: { session, context, endedAt in
                try WorkoutSessionLifecycle.end(session, in: context, endedAt: endedAt)
            },
            discardSession: { session, context in
                try WorkoutSessionLifecycle.discard(session, in: context)
            },
            createSession: { template, context, startedAt, timeZone in
                try WorkoutSessionLifecycle.createSession(
                    for: template,
                    in: context,
                    startedAt: startedAt,
                    timeZone: timeZone
                )
            }
        )
    }

    static func resolve(
        choice: Choice,
        for template: Template,
        in context: ModelContext,
        resolvedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> WorkoutSession {
        try resolve(
            choice: choice,
            for: template,
            in: context,
            resolvedAt: resolvedAt,
            timeZone: timeZone,
            notificationCanceller: .live,
            dependencies: .live
        )
    }

    static func resolve(
        choice: Choice,
        for template: Template,
        in context: ModelContext,
        resolvedAt: Date = Date(),
        timeZone: TimeZone = .current,
        notificationCanceller: NotificationCanceller
    ) throws -> WorkoutSession {
        try resolve(
            choice: choice,
            for: template,
            in: context,
            resolvedAt: resolvedAt,
            timeZone: timeZone,
            notificationCanceller: notificationCanceller,
            dependencies: .live
        )
    }

    static func resolve(
        choice: Choice,
        for template: Template,
        in context: ModelContext,
        resolvedAt: Date = Date(),
        timeZone: TimeZone = .current,
        notificationCanceller: NotificationCanceller,
        dependencies: Dependencies
    ) throws -> WorkoutSession {
        let openSession = try dependencies.currentOpenSession(context)

        if let openSession {
            switch choice {
            case .endCurrentAndCreate:
                try dependencies.endSession(openSession, context, resolvedAt)
            case .discardCurrentAndCreate:
                try dependencies.discardSession(openSession, context)
            }
        }

        let newSession = try dependencies.createSession(template, context, resolvedAt, timeZone)
        notificationCanceller.cancelRestCompletionNotification()

        return newSession
    }
}
