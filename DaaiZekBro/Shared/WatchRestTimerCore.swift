import Foundation

struct WatchRestTimerState: Equatable {
    var sessionID: String
    var exerciseOrderIndex: Int
    var exerciseName: String
    var startedAt: Date
    var endsAt: Date
    var totalSeconds: Int
    var remainingSeconds: Int
    var isZeroed: Bool
    var didPlayCompletionHaptic: Bool

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }

        return min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }
}

enum WatchRestTimerEffect: Equatable {
    case none
    case playCompletionHaptic
}

struct WatchRestTimerCore: Equatable {
    private(set) var state: WatchRestTimerState?

    private var hasPendingCompletionHaptic: Bool

    init() {
        state = nil
        hasPendingCompletionHaptic = false
    }

    mutating func start(
        sessionID: String,
        exerciseOrderIndex: Int,
        exerciseName: String,
        restSeconds: Int,
        startedAt: Date,
        now: Date
    ) -> WatchRestTimerEffect {
        let safeRestSeconds = max(1, restSeconds)
        let endsAt = startedAt.addingTimeInterval(TimeInterval(safeRestSeconds))
        let remainingSeconds = Self.secondsRemaining(until: endsAt, now: now)

        hasPendingCompletionHaptic = false
        state = WatchRestTimerState(
            sessionID: sessionID,
            exerciseOrderIndex: exerciseOrderIndex,
            exerciseName: exerciseName,
            startedAt: startedAt,
            endsAt: endsAt,
            totalSeconds: safeRestSeconds,
            remainingSeconds: remainingSeconds,
            isZeroed: remainingSeconds == 0,
            didPlayCompletionHaptic: false
        )

        return .none
    }

    mutating func refresh(now: Date, isActive: Bool, canNotify: Bool) -> WatchRestTimerEffect {
        guard var currentState = state else {
            hasPendingCompletionHaptic = false
            return .none
        }

        let wasZeroed = currentState.isZeroed
        let remainingSeconds = Self.secondsRemaining(until: currentState.endsAt, now: now)
        currentState.remainingSeconds = remainingSeconds
        currentState.isZeroed = remainingSeconds == 0

        guard currentState.isZeroed else {
            hasPendingCompletionHaptic = false
            state = currentState
            return .none
        }

        guard currentState.didPlayCompletionHaptic == false else {
            state = currentState
            return .none
        }

        if isActive, wasZeroed == false || hasPendingCompletionHaptic {
            currentState.didPlayCompletionHaptic = true
            hasPendingCompletionHaptic = false
            state = currentState
            return .playCompletionHaptic
        }

        if wasZeroed == false, isActive == false, canNotify {
            hasPendingCompletionHaptic = true
        } else if wasZeroed == false {
            hasPendingCompletionHaptic = false
        }

        state = currentState
        return .none
    }

    func displayState(now: Date) -> WatchRestTimerState? {
        guard var currentState = state else {
            return nil
        }

        let remainingSeconds = Self.secondsRemaining(until: currentState.endsAt, now: now)
        currentState.remainingSeconds = remainingSeconds
        currentState.isZeroed = remainingSeconds == 0
        return currentState
    }

    mutating func addThirtySeconds(now: Date) -> WatchRestTimerEffect {
        guard var currentState = state else {
            hasPendingCompletionHaptic = false
            return .none
        }

        let remainingSeconds = Self.secondsRemaining(until: currentState.endsAt, now: now)

        if currentState.isZeroed || remainingSeconds == 0 {
            let endsAt = now.addingTimeInterval(30)

            currentState.startedAt = now
            currentState.endsAt = endsAt
            currentState.totalSeconds = 30
            currentState.remainingSeconds = 30
            currentState.isZeroed = false
            currentState.didPlayCompletionHaptic = false
        } else {
            currentState.endsAt = currentState.endsAt.addingTimeInterval(30)
            currentState.totalSeconds += 30
            currentState.remainingSeconds = Self.secondsRemaining(until: currentState.endsAt, now: now)
            currentState.isZeroed = false
        }

        hasPendingCompletionHaptic = false
        state = currentState
        return .none
    }

    mutating func skip() {
        state = nil
        hasPendingCompletionHaptic = false
    }

    private static func secondsRemaining(until endDate: Date, now: Date) -> Int {
        max(0, Int(ceil(endDate.timeIntervalSince(now))))
    }
}

enum WatchRestTimerCompletedSide: Equatable {
    case left
    case right
}

enum WatchRestTimerStartPolicy {
    static func shouldStartAfterCompletedSet(
        isUnilateral: Bool,
        completedSide: WatchRestTimerCompletedSide?
    ) -> Bool {
        if isUnilateral {
            return completedSide == .right
        }

        return true
    }
}
