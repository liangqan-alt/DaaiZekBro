import Foundation
import Testing
@testable import DaaiZekBro

@MainActor
struct RestTimerTests {
    @Test func startingTimerSchedulesNotificationAtEndDate() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scheduler = FakeRestNotificationScheduler()
        let timer = RestTimerModel(scheduler: scheduler, now: { now })
        let sessionID = UUID()

        await timer.start(
            restSeconds: 90,
            sessionID: sessionID,
            exerciseName: "固定器械卧推",
            startedAt: now
        )

        #expect(timer.state?.remainingSeconds == 90)
        #expect(timer.state?.endsAt == now.addingTimeInterval(90))
        #expect(timer.state?.notificationStatus == .scheduled)
        #expect(scheduler.events == [
            .cancel,
            .schedule(sessionID, "固定器械卧推", now.addingTimeInterval(90)),
        ])
    }

    @Test func addThirtySecondsReplacesPendingNotification() async throws {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let scheduler = FakeRestNotificationScheduler()
        let timer = RestTimerModel(scheduler: scheduler, now: { currentDate })
        let sessionID = UUID()

        await timer.start(
            restSeconds: 90,
            sessionID: sessionID,
            exerciseName: "固定器械卧推",
            startedAt: currentDate
        )

        currentDate = currentDate.addingTimeInterval(10)
        timer.tick(now: currentDate)
        await timer.addThirtySeconds()

        #expect(timer.state?.remainingSeconds == 110)
        #expect(timer.state?.endsAt == Date(timeIntervalSince1970: 1_120))
        #expect(scheduler.events == [
            .cancel,
            .schedule(sessionID, "固定器械卧推", Date(timeIntervalSince1970: 1_090)),
            .cancel,
            .schedule(sessionID, "固定器械卧推", Date(timeIntervalSince1970: 1_120)),
        ])
    }

    @Test func skipClearsStateAndCancelsPendingNotification() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scheduler = FakeRestNotificationScheduler()
        let timer = RestTimerModel(scheduler: scheduler, now: { now })
        let sessionID = UUID()

        await timer.start(
            restSeconds: 90,
            sessionID: sessionID,
            exerciseName: "固定器械卧推",
            startedAt: now
        )
        await timer.skip()

        #expect(timer.state == nil)
        #expect(scheduler.events == [
            .cancel,
            .schedule(sessionID, "固定器械卧推", now.addingTimeInterval(90)),
            .cancel,
        ])
    }

    @Test func stoppingForegroundTimerKeepsScheduledNotification() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scheduler = FakeRestNotificationScheduler()
        let timer = RestTimerModel(scheduler: scheduler, now: { now })
        let sessionID = UUID()

        await timer.start(
            restSeconds: 90,
            sessionID: sessionID,
            exerciseName: "固定器械卧推",
            startedAt: now
        )
        timer.stopForegroundTimerKeepingNotification()

        #expect(timer.state == nil)
        #expect(scheduler.events == [
            .cancel,
            .schedule(sessionID, "固定器械卧推", now.addingTimeInterval(90)),
        ])
    }

    @Test func notificationDeniedKeepsForegroundTimerUsable() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scheduler = FakeRestNotificationScheduler(result: .notificationsDisabled)
        let timer = RestTimerModel(scheduler: scheduler, now: { now })

        await timer.start(
            restSeconds: 90,
            sessionID: UUID(),
            exerciseName: "固定器械卧推",
            startedAt: now
        )

        #expect(timer.state?.remainingSeconds == 90)
        #expect(timer.state?.notificationStatus == .notificationsDisabled)
        #expect(scheduler.events == [.cancel])
    }

    @Test func startingAnotherTimerReplacesExistingNotification() async throws {
        let firstStart = Date(timeIntervalSince1970: 1_000)
        let secondStart = Date(timeIntervalSince1970: 1_030)
        let scheduler = FakeRestNotificationScheduler()
        let timer = RestTimerModel(scheduler: scheduler, now: { secondStart })
        let sessionID = UUID()

        await timer.start(
            restSeconds: 90,
            sessionID: sessionID,
            exerciseName: "固定器械卧推",
            startedAt: firstStart
        )
        await timer.start(
            restSeconds: 60,
            sessionID: sessionID,
            exerciseName: "固定器械卧推",
            startedAt: secondStart
        )

        #expect(timer.state?.remainingSeconds == 60)
        #expect(timer.state?.endsAt == secondStart.addingTimeInterval(60))
        #expect(scheduler.events == [
            .cancel,
            .schedule(sessionID, "固定器械卧推", firstStart.addingTimeInterval(90)),
            .cancel,
            .schedule(sessionID, "固定器械卧推", secondStart.addingTimeInterval(60)),
        ])
    }

    @Test func tickFinishesTimerAtEndDate() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let scheduler = FakeRestNotificationScheduler()
        let timer = RestTimerModel(scheduler: scheduler, now: { now })

        await timer.start(
            restSeconds: 90,
            sessionID: UUID(),
            exerciseName: "固定器械卧推",
            startedAt: now
        )

        let didFinish = timer.tick(now: now.addingTimeInterval(90))

        #expect(didFinish)
        #expect(timer.state == nil)
    }

    @Test func restTimerStartsForBilateralAndUnilateralRightOnly() {
        #expect(RestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: false,
            completedSide: nil
        ))
        #expect(RestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: true,
            completedSide: .left
        ) == false)
        #expect(RestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: true,
            completedSide: .right
        ))
        #expect(RestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: true,
            completedSide: nil
        ) == false)
    }
}

@MainActor
private final class FakeRestNotificationScheduler: RestNotificationScheduling {
    enum Event: Equatable {
        case cancel
        case schedule(UUID, String, Date)
    }

    private let result: RestNotificationSchedulingResult
    private(set) var events: [Event] = []

    init(result: RestNotificationSchedulingResult = .scheduled) {
        self.result = result
    }

    func replaceRestCompletionNotification(
        sessionID: UUID,
        exerciseName: String,
        deliverAt: Date
    ) async throws -> RestNotificationSchedulingResult {
        events.append(.cancel)

        if result == .scheduled {
            events.append(.schedule(sessionID, exerciseName, deliverAt))
        }

        return result
    }

    func cancelRestCompletionNotification() async {
        events.append(.cancel)
    }
}
