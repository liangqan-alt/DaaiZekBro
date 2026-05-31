import Foundation

struct WatchRecordDraft: Equatable {
    var weight: Double
    var reps: Int
    var rpe: Int?
    var side: String?
    let reference: WatchWorkoutSnapshot.LastSetReference?

    nonisolated init(
        weight: Double,
        reps: Int,
        rpe: Int?,
        side: String?,
        reference: WatchWorkoutSnapshot.LastSetReference? = nil
    ) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.side = side
        self.reference = reference
    }

    nonisolated init(
        isUnilateral: Bool,
        leftCompletedSetCount: Int,
        rightCompletedSetCount: Int,
        reference: WatchWorkoutSnapshot.LastSetReference? = nil
    ) {
        self.weight = 0
        self.reps = 10
        self.rpe = nil
        self.side = isUnilateral
            ? Self.inferredNextSide(leftCompletedSetCount: leftCompletedSetCount, rightCompletedSetCount: rightCompletedSetCount)
            : nil
        self.reference = reference
    }

    nonisolated var canSubmitWeightAndReps: Bool {
        weight.isFinite && weight >= 0 && reps >= 1
    }

    nonisolated func canSubmit(isUnilateral: Bool) -> Bool {
        let hasValidRPE = rpe.map { 6...10 ~= $0 } ?? true

        if isUnilateral {
            return canSubmitWeightAndReps && hasValidRPE && (side == "left" || side == "right")
        }

        return canSubmitWeightAndReps && hasValidRPE && side == nil
    }

    mutating nonisolated func adjustWeight(by delta: Double) {
        weight = max(0, roundedToHalfStep(weight + delta))
    }

    mutating nonisolated func adjustReps(by delta: Int) {
        reps = max(1, reps + delta)
    }

    mutating nonisolated func toggleRPE(_ value: Int) {
        guard 6...10 ~= value else { return }
        rpe = rpe == value ? nil : value
    }

    mutating nonisolated func selectSide(_ value: String) {
        guard value == "left" || value == "right" else { return }
        side = value
    }

    nonisolated static func inferredNextSide(
        leftCompletedSetCount: Int,
        rightCompletedSetCount: Int
    ) -> String {
        leftCompletedSetCount > rightCompletedSetCount ? "right" : "left"
    }

    private nonisolated func roundedToHalfStep(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }
}
