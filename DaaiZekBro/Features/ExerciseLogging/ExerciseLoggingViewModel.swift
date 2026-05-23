import Foundation
import Observation

@MainActor
@Observable
final class ExerciseLoggingViewModel {
    var selectedSide: Side = .left
    var weightText = ""
    var repsText = ""
    var selectedRPE: Int?
    var isRPEExpanded = false
    var errorMessage: String?
    var didLoadInitialDraft = false

    var parsedWeight: Double? {
        let normalizedText = weightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard normalizedText.isEmpty == false,
              let value = Double(normalizedText),
              value.isFinite,
              value >= 0
        else {
            return nil
        }

        return value
    }

    var parsedReps: Int? {
        let trimmedText = repsText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedText.isEmpty == false, let reps = Int(trimmedText), reps >= 1 else {
            return nil
        }

        return reps
    }

    func adjustWeight(by delta: Double) {
        let currentWeight = parsedWeight ?? 0
        weightText = Self.displayWeight(max(0, currentWeight + delta))
    }

    func adjustReps(by delta: Int) {
        let currentReps = parsedReps ?? 0
        repsText = "\(max(1, currentReps + delta))"
    }

    func currentSide(isUnilateral: Bool) -> Side? {
        isUnilateral ? selectedSide : nil
    }

    func applyPrefill(_ values: WorkoutSetValues?) {
        guard let values else {
            weightText = ""
            repsText = ""
            selectedRPE = nil
            return
        }

        weightText = Self.displayWeight(values.weight)
        repsText = "\(values.reps)"
        selectedRPE = nil
    }

    func canCompleteSet(
        sessionEnded: Bool,
        isUnilateral: Bool,
        leftCount: Int,
        rightCount: Int
    ) -> Bool {
        sessionEnded == false
            && parsedWeight != nil
            && parsedReps != nil
            && selectedSideMatchesBalance(
                isUnilateral: isUnilateral,
                leftCount: leftCount,
                rightCount: rightCount
            )
    }

    func sidePrompt(isUnilateral: Bool, leftCount: Int, rightCount: Int) -> String? {
        guard isUnilateral else { return nil }

        if leftCount > rightCount {
            return "上一组左侧已完成，请完成右侧"
        }

        if leftCount < rightCount {
            return "上一组右侧已完成，请完成左侧"
        }

        return nil
    }

    func selectedSideMatchesBalance(isUnilateral: Bool, leftCount: Int, rightCount: Int) -> Bool {
        guard isUnilateral else {
            return true
        }

        if leftCount > rightCount {
            return selectedSide == .right
        }

        if leftCount < rightCount {
            return selectedSide == .left
        }

        return true
    }

    func completionButtonTitle(isUnilateral: Bool) -> String {
        guard isUnilateral else {
            return "完成本组 · 开始计时"
        }

        switch selectedSide {
        case .left:
            return "完成左侧"
        case .right:
            return "完成右侧 · 开始计时"
        }
    }

    func sortedSets(_ sets: [WorkoutSet]) -> [WorkoutSet] {
        sets.sorted { lhs, rhs in
            if lhs.completedAt != rhs.completedAt {
                return lhs.completedAt < rhs.completedAt
            }

            return lhs.setIndex < rhs.setIndex
        }
    }

    func leftSets(from sets: [WorkoutSet]) -> [WorkoutSet] {
        sortedSets(sets).filter { $0.side == .left }
    }

    func rightSets(from sets: [WorkoutSet]) -> [WorkoutSet] {
        sortedSets(sets).filter { $0.side == .right }
    }

    func bilateralSets(from sets: [WorkoutSet]) -> [WorkoutSet] {
        sortedSets(sets).filter { $0.side == nil }
    }

    private static func displayWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return "\(Int(weight))"
        }

        return String(format: "%.1f", weight)
    }
}
