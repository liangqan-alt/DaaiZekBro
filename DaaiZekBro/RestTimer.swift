import Combine
import Foundation
import SwiftUI
import UserNotifications

enum RestNotificationSchedulingResult: Equatable {
    case scheduled
    case notificationsDisabled
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

enum RestNotificationStatus: Equatable {
    case pendingPermission
    case scheduled
    case notificationsDisabled
    case failed(String)
}

struct RestTimerState: Equatable, Identifiable {
    let id: UUID
    let sessionID: UUID
    let exerciseName: String
    let startedAt: Date
    var endsAt: Date
    var totalSeconds: Int
    var remainingSeconds: Int
    var notificationStatus: RestNotificationStatus

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }

        return min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }
}

@MainActor
final class RestTimerModel: ObservableObject {
    @Published private(set) var state: RestTimerState?

    private let scheduler: any RestNotificationScheduling
    private let now: () -> Date

    convenience init(now: @escaping () -> Date = { Date() }) {
        self.init(scheduler: UserNotificationRestScheduler(), now: now)
    }

    init(
        scheduler: any RestNotificationScheduling,
        now: @escaping () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.now = now
    }

    func start(
        restSeconds: Int,
        sessionID: UUID,
        exerciseName: String,
        startedAt: Date? = nil
    ) async {
        let safeRestSeconds = max(1, restSeconds)
        let startDate = startedAt ?? now()
        let endsAt = startDate.addingTimeInterval(TimeInterval(safeRestSeconds))
        let timerID = UUID()
        let initialState = RestTimerState(
            id: timerID,
            sessionID: sessionID,
            exerciseName: exerciseName,
            startedAt: startDate,
            endsAt: endsAt,
            totalSeconds: safeRestSeconds,
            remainingSeconds: Self.secondsRemaining(until: endsAt, now: now()),
            notificationStatus: .pendingPermission
        )

        state = initialState
        await replaceNotification(for: timerID, sessionID: sessionID, exerciseName: exerciseName, deliverAt: endsAt)
    }

    func addThirtySeconds() async {
        guard var currentState = state else { return }

        currentState.totalSeconds += 30
        currentState.endsAt = currentState.endsAt.addingTimeInterval(30)
        currentState.remainingSeconds = Self.secondsRemaining(until: currentState.endsAt, now: now())
        currentState.notificationStatus = .pendingPermission
        state = currentState

        await replaceNotification(
            for: currentState.id,
            sessionID: currentState.sessionID,
            exerciseName: currentState.exerciseName,
            deliverAt: currentState.endsAt
        )
    }

    func skip() async {
        state = nil
        await scheduler.cancelRestCompletionNotification()
    }

    func stopForegroundTimerKeepingNotification() {
        state = nil
    }

    @discardableResult
    func tick(now date: Date) -> Bool {
        guard var currentState = state else { return false }

        let remainingSeconds = Self.secondsRemaining(until: currentState.endsAt, now: date)

        guard remainingSeconds > 0 else {
            state = nil
            return true
        }

        currentState.remainingSeconds = remainingSeconds
        state = currentState
        return false
    }

    private func replaceNotification(
        for timerID: UUID,
        sessionID: UUID,
        exerciseName: String,
        deliverAt: Date
    ) async {
        do {
            let result = try await scheduler.replaceRestCompletionNotification(
                sessionID: sessionID,
                exerciseName: exerciseName,
                deliverAt: deliverAt
            )

            guard Task.isCancelled == false, state?.id == timerID else { return }

            state?.notificationStatus = result == .scheduled ? .scheduled : .notificationsDisabled
        } catch is CancellationError {
            return
        } catch {
            guard Task.isCancelled == false, state?.id == timerID else { return }

            state?.notificationStatus = .failed(error.localizedDescription)
        }
    }

    private static func secondsRemaining(until endDate: Date, now: Date) -> Int {
        max(0, Int(ceil(endDate.timeIntervalSince(now))))
    }
}

enum RestTimerStartPolicy {
    static func shouldStartAfterCompletedSet(isUnilateral: Bool, completedSide: Side?) -> Bool {
        if isUnilateral {
            return completedSide == .right
        }

        return true
    }
}

struct RestTimerView: View {
    let state: RestTimerState
    let addThirtySeconds: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            notificationStatusBanner

            ZStack {
                Circle()
                    .fill(DZColor.cream50)
                    .shadow(color: DZColor.ink900.opacity(0.10), radius: 16, x: 0, y: 8)

                Circle()
                    .stroke(DZColor.cream300, lineWidth: 12)
                    .padding(10)

                Circle()
                    .trim(from: 0, to: state.progress)
                    .stroke(
                        DZColor.pump500,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(10)

                VStack(spacing: 4) {
                    Text(formattedTime(state.remainingSeconds))
                        .dzNumeric(size: 36, weight: .bold)
                        .foregroundStyle(DZColor.ink900)

                    Text("休息 \(state.totalSeconds) 秒")
                        .font(.footnote)
                        .foregroundStyle(DZColor.ink700)
                }
            }
            .frame(width: 148, height: 148)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("rest-timer-ring")

            HStack {
                Button("+30 秒", action: addThirtySeconds)
                    .buttonStyle(DZSecondaryButtonStyle())
                    .accessibilityIdentifier("extend-rest-timer-button")

                Button("跳过", role: .destructive, action: skip)
                    .buttonStyle(DZDestructiveButtonStyle())
                    .accessibilityIdentifier("skip-rest-timer-button")
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var notificationStatusBanner: some View {
        switch state.notificationStatus {
        case .notificationsDisabled:
            Text("未开启通知，仅前台显示")
                .font(.footnote)
                .foregroundStyle(DZColor.ink700)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            Text("通知调度失败，仅前台显示")
                .font(.footnote)
                .foregroundStyle(DZColor.ink700)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .pendingPermission, .scheduled:
            EmptyView()
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
