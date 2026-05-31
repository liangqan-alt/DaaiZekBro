import Foundation
import Testing
@testable import DaaiZekBro

@MainActor
struct WatchRestTimerCoreTests {
    @Test func startCreatesActiveStateUsingWallClockRemaining() throws {
        var core = WatchRestTimerCore()
        let startedAt = WatchRestTimerTestDates.at(0)
        let now = WatchRestTimerTestDates.at(15)

        _ = core.start(
            sessionID: "session-1",
            exerciseOrderIndex: 2,
            exerciseName: "Bench Press",
            restSeconds: 90,
            startedAt: startedAt,
            now: now
        )

        let state = try #require(core.state)
        #expect(state.sessionID == "session-1")
        #expect(state.exerciseOrderIndex == 2)
        #expect(state.exerciseName == "Bench Press")
        #expect(state.startedAt == startedAt)
        #expect(state.endsAt == WatchRestTimerTestDates.at(90))
        #expect(state.remainingSeconds == 75)
    }

    @Test func startClampsRestSecondsToAtLeastOne() throws {
        var core = WatchRestTimerCore()
        let startedAt = WatchRestTimerTestDates.at(0)

        _ = core.start(
            sessionID: "session-1",
            exerciseOrderIndex: 0,
            exerciseName: "Dip",
            restSeconds: 0,
            startedAt: startedAt,
            now: startedAt
        )

        let state = try #require(core.state)
        #expect(state.endsAt == WatchRestTimerTestDates.at(1))
        #expect(state.remainingSeconds == 1)
    }

    @Test func refreshUpdatesRemainingFromWallClock() throws {
        var core = startedCore(restSeconds: 90)

        let effect = core.refresh(
            now: WatchRestTimerTestDates.at(31),
            isActive: true,
            canNotify: true
        )

        #expect(effect == .none)
        #expect(try #require(core.state).remainingSeconds == 59)
    }

    @Test func activeForegroundCompletionPlaysHapticOnce() throws {
        var core = startedCore(restSeconds: 10)

        let firstEffect = core.refresh(
            now: WatchRestTimerTestDates.at(10),
            isActive: true,
            canNotify: true
        )
        let secondEffect = core.refresh(
            now: WatchRestTimerTestDates.at(11),
            isActive: true,
            canNotify: true
        )

        #expect(firstEffect == .playCompletionHaptic)
        #expect(secondEffect == .none)
        #expect(try #require(core.state).remainingSeconds == 0)
    }

    @Test func inactiveCompletionQueuesHapticForNextActiveRefresh() throws {
        var core = startedCore(restSeconds: 10)

        let inactiveEffect = core.refresh(
            now: WatchRestTimerTestDates.at(10),
            isActive: false,
            canNotify: true
        )
        let activeEffect = core.refresh(
            now: WatchRestTimerTestDates.at(12),
            isActive: true,
            canNotify: true
        )
        let repeatedActiveEffect = core.refresh(
            now: WatchRestTimerTestDates.at(13),
            isActive: true,
            canNotify: true
        )

        #expect(inactiveEffect == .none)
        #expect(activeEffect == .playCompletionHaptic)
        #expect(repeatedActiveEffect == .none)
        #expect(try #require(core.state).remainingSeconds == 0)
    }

    @Test func notificationDisabledCompletionDoesNotQueueHaptic() throws {
        var core = startedCore(restSeconds: 10)

        let inactiveEffect = core.refresh(
            now: WatchRestTimerTestDates.at(10),
            isActive: false,
            canNotify: false
        )
        let activeEffect = core.refresh(
            now: WatchRestTimerTestDates.at(12),
            isActive: true,
            canNotify: true
        )

        #expect(inactiveEffect == .none)
        #expect(activeEffect == .none)
        #expect(try #require(core.state).remainingSeconds == 0)
    }

    @Test func displayStateUpdatesRemainingWithoutConsumingAuthorizedDeferredHaptic() throws {
        var core = startedCore(restSeconds: 10)

        let displayState = try #require(core.displayState(now: WatchRestTimerTestDates.at(12)))
        let unchangedCoreState = try #require(core.state)
        #expect(displayState.remainingSeconds == 0)
        #expect(displayState.isZeroed)
        #expect(unchangedCoreState.remainingSeconds == 10)
        #expect(unchangedCoreState.isZeroed == false)

        let inactiveEffect = core.refresh(
            now: WatchRestTimerTestDates.at(12),
            isActive: false,
            canNotify: true
        )
        let activeEffect = core.refresh(
            now: WatchRestTimerTestDates.at(13),
            isActive: true,
            canNotify: true
        )

        #expect(inactiveEffect == .none)
        #expect(activeEffect == .playCompletionHaptic)
    }

    @Test func displayStateUpdatesRemainingWithoutCreatingUnauthorizedDeferredHaptic() throws {
        var core = startedCore(restSeconds: 10)

        let displayState = try #require(core.displayState(now: WatchRestTimerTestDates.at(12)))
        #expect(displayState.remainingSeconds == 0)
        #expect(displayState.isZeroed)

        let inactiveEffect = core.refresh(
            now: WatchRestTimerTestDates.at(12),
            isActive: false,
            canNotify: false
        )
        let activeEffect = core.refresh(
            now: WatchRestTimerTestDates.at(13),
            isActive: true,
            canNotify: true
        )

        #expect(inactiveEffect == .none)
        #expect(activeEffect == .none)
    }

    @Test func addThirtySecondsExtendsRunningTimerFromEndDate() throws {
        var core = startedCore(restSeconds: 60)
        _ = core.refresh(
            now: WatchRestTimerTestDates.at(10),
            isActive: true,
            canNotify: true
        )

        _ = core.addThirtySeconds(now: WatchRestTimerTestDates.at(10))

        let state = try #require(core.state)
        #expect(state.endsAt == WatchRestTimerTestDates.at(90))
        #expect(state.remainingSeconds == 80)
    }

    @Test func addThirtySecondsRestartsZeroedTimerFromNow() throws {
        var core = startedCore(restSeconds: 10)
        _ = core.refresh(
            now: WatchRestTimerTestDates.at(10),
            isActive: false,
            canNotify: false
        )

        _ = core.addThirtySeconds(now: WatchRestTimerTestDates.at(25))

        let state = try #require(core.state)
        #expect(state.startedAt == WatchRestTimerTestDates.at(25))
        #expect(state.endsAt == WatchRestTimerTestDates.at(55))
        #expect(state.remainingSeconds == 30)
    }

    @Test func skipClearsStateAndPendingHaptic() {
        var core = startedCore(restSeconds: 10)
        _ = core.refresh(
            now: WatchRestTimerTestDates.at(10),
            isActive: false,
            canNotify: true
        )

        core.skip()
        let effect = core.refresh(
            now: WatchRestTimerTestDates.at(12),
            isActive: true,
            canNotify: true
        )

        #expect(core.state == nil)
        #expect(effect == .none)
    }

    @Test func startPolicyStartsForBilateralAndUnilateralRightOnly() {
        #expect(WatchRestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: false,
            completedSide: nil
        ))
        #expect(WatchRestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: true,
            completedSide: .left
        ) == false)
        #expect(WatchRestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: true,
            completedSide: .right
        ))
        #expect(WatchRestTimerStartPolicy.shouldStartAfterCompletedSet(
            isUnilateral: true,
            completedSide: nil
        ) == false)
    }

    private func startedCore(restSeconds: Int) -> WatchRestTimerCore {
        var core = WatchRestTimerCore()
        _ = core.start(
            sessionID: "session-1",
            exerciseOrderIndex: 1,
            exerciseName: "Bench Press",
            restSeconds: restSeconds,
            startedAt: WatchRestTimerTestDates.at(0),
            now: WatchRestTimerTestDates.at(0)
        )
        return core
    }
}

private enum WatchRestTimerTestDates {
    static func at(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }
}
