import Combine
import Foundation
import SwiftData
import UIKit
import UserNotifications

struct RestNotificationPayload: Equatable {
    static let sessionIDKey = "sessionId"
    static let exerciseNameKey = "exerciseName"

    let sessionID: UUID
    let exerciseName: String

    init(sessionID: UUID, exerciseName: String) {
        self.sessionID = sessionID
        self.exerciseName = exerciseName
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let sessionIDString = userInfo[Self.sessionIDKey] as? String,
            let sessionID = UUID(uuidString: sessionIDString),
            let exerciseName = userInfo[Self.exerciseNameKey] as? String,
            exerciseName.isEmpty == false
        else {
            return nil
        }

        self.sessionID = sessionID
        self.exerciseName = exerciseName
    }

    var userInfo: [AnyHashable: Any] {
        [
            Self.sessionIDKey: sessionID.uuidString,
            Self.exerciseNameKey: exerciseName,
        ]
    }
}

@MainActor
final class NotificationNavigationRouter: ObservableObject {
    @Published private(set) var pendingRestNotification: RestNotificationPayload?

    func handle(_ payload: RestNotificationPayload) {
        pendingRestNotification = payload
    }

    func consume(_ payload: RestNotificationPayload) {
        guard pendingRestNotification == payload else { return }

        pendingRestNotification = nil
    }
}

@MainActor
enum NotificationNavigationResolver {
    static func route(for payload: RestNotificationPayload, in context: ModelContext) throws -> [AppRoute] {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        guard let session = sessions.first(where: { $0.id == payload.sessionID }), session.endedAt == nil else {
            return []
        }

        return [
            .currentWorkout(sessionID: session.id),
            .exerciseLogging(sessionID: session.id, exerciseName: payload.exerciseName),
        ]
    }
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var notificationRouter: NotificationNavigationRouter? {
        didSet {
            Task { @MainActor in
                flushPendingPayload()
            }
        }
    }
    private var pendingPayload: RestNotificationPayload?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request

        guard
            request.identifier == UserNotificationRestScheduler.notificationIdentifier,
            let payload = RestNotificationPayload(userInfo: request.content.userInfo)
        else {
            return
        }

        await deliver(payload)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier == UserNotificationRestScheduler.notificationIdentifier else {
            return []
        }

        return [.banner, .sound]
    }

    private func deliver(_ payload: RestNotificationPayload) async {
        await MainActor.run {
            if let notificationRouter {
                notificationRouter.handle(payload)
            } else {
                pendingPayload = payload
            }
        }
    }

    @MainActor
    private func flushPendingPayload() {
        guard let pendingPayload, let notificationRouter else {
            return
        }

        notificationRouter.handle(pendingPayload)
        self.pendingPayload = nil
    }
}
