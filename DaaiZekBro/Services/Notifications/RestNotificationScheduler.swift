import Foundation
import UserNotifications

enum RestNotificationSchedulingResult: Equatable {
    case scheduled
    case notificationsDisabled
}

enum RestNotificationStatus: Equatable {
    case pendingPermission
    case scheduled
    case notificationsDisabled
    case failed(String)
}

@MainActor
protocol RestNotificationScheduling {
    func replaceRestCompletionNotification(
        sessionID: UUID,
        exerciseName: String,
        deliverAt: Date
    ) async throws -> RestNotificationSchedulingResult

    func cancelRestCompletionNotification() async
}

struct UserNotificationRestScheduler: RestNotificationScheduling {
    static let notificationIdentifier = "rest-timer"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    static func cancelPendingRestCompletionNotification(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
    }

    func replaceRestCompletionNotification(
        sessionID: UUID,
        exerciseName: String,
        deliverAt: Date
    ) async throws -> RestNotificationSchedulingResult {
        try Task.checkCancellation()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])

        guard try await ensureNotificationAuthorization() else {
            return .notificationsDisabled
        }

        try Task.checkCancellation()

        let payload = RestNotificationPayload(sessionID: sessionID, exerciseName: exerciseName)
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "\(exerciseName) 下一组可以开始了"
        content.sound = .default
        content.userInfo = payload.userInfo

        let interval = max(1, deliverAt.timeIntervalSince(Date()))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        try Task.checkCancellation()
        try await center.add(request)

        return .scheduled
    }

    func cancelRestCompletionNotification() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }

    private func ensureNotificationAuthorization() async throws -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        @unknown default:
            return false
        }
    }
}
