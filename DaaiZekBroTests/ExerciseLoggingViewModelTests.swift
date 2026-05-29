import Foundation
import Testing
@testable import DaaiZekBro

@MainActor
struct ExerciseLoggingViewModelTests {
    @Test func parsesWeightAndRepsFromDraftText() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightText = " 24,5 "
        viewModel.repsText = " 8 "

        #expect(viewModel.parsedWeight == 24.5)
        #expect(viewModel.parsedWeightKilograms == 24.5)
        #expect(viewModel.parsedReps == 8)

        viewModel.weightText = ""
        viewModel.repsText = ""

        #expect(viewModel.parsedWeight == nil)
        #expect(viewModel.parsedWeightKilograms == nil)
        #expect(viewModel.parsedReps == nil)

        viewModel.weightText = "-1"
        viewModel.repsText = "0"

        #expect(viewModel.parsedWeight == nil)
        #expect(viewModel.parsedWeightKilograms == nil)
        #expect(viewModel.parsedReps == nil)

        viewModel.weightText = "inf"
        viewModel.repsText = "1.5"

        #expect(viewModel.parsedWeight == nil)
        #expect(viewModel.parsedWeightKilograms == nil)
        #expect(viewModel.parsedReps == nil)
    }

    @Test func parsesDisplayWeightInSelectedUnitAndExposesKilograms() {
        let viewModel = ExerciseLoggingViewModel()

        #expect(viewModel.weightUnit == .kilograms)

        viewModel.weightUnit = .pounds
        viewModel.weightText = " 44,1 "
        viewModel.repsText = " 8 "

        #expect(viewModel.parsedWeight == 44.1)
        #expect(abs((viewModel.parsedWeightKilograms ?? 0) - 20.0034072) < 0.000001)
        #expect(viewModel.parsedReps == 8)
    }

    @Test func adjustersClampWeightAndReps() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightText = "1"
        viewModel.adjustWeight(by: -2.5)
        #expect(viewModel.weightText == "0")

        viewModel.adjustWeight(by: 2.5)
        #expect(viewModel.weightText == "2.5")

        viewModel.adjustWeight(by: 2.5)
        #expect(viewModel.weightText == "5")

        viewModel.repsText = "1"
        viewModel.adjustReps(by: -1)
        #expect(viewModel.repsText == "1")

        viewModel.adjustReps(by: 2)
        #expect(viewModel.repsText == "3")

        viewModel.repsText = "bad"
        viewModel.adjustReps(by: -1)
        #expect(viewModel.repsText == "1")
    }

    @Test func adjustWeightUsesSelectedDisplayUnit() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightUnit = .pounds
        viewModel.weightText = "1"

        viewModel.adjustWeight(by: 2.5)
        #expect(viewModel.weightText == "3.5")
        #expect(abs((viewModel.parsedWeightKilograms ?? 0) - 1.587572) < 0.000001)

        viewModel.adjustWeight(by: -10)
        #expect(viewModel.weightText == "0")
        #expect(viewModel.parsedWeightKilograms == 0)
    }

    @Test func applyPrefillClearsOrLoadsDraftValues() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightText = "20"
        viewModel.repsText = "10"
        viewModel.selectedRPE = 8
        viewModel.applyPrefill(nil)

        #expect(viewModel.weightText == "")
        #expect(viewModel.repsText == "")
        #expect(viewModel.selectedRPE == nil)

        viewModel.selectedRPE = 9
        viewModel.applyPrefill(WorkoutSetValues(weight: 22.5, reps: 12))

        #expect(viewModel.weightText == "22.5")
        #expect(viewModel.repsText == "12")
        #expect(viewModel.selectedRPE == nil)

        viewModel.applyPrefill(WorkoutSetValues(weight: 24, reps: 8))

        #expect(viewModel.weightText == "24")
        #expect(viewModel.repsText == "8")
    }

    @Test func applyPrefillConvertsKilogramsToSelectedDisplayUnit() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightUnit = .pounds
        viewModel.selectedRPE = 9
        viewModel.applyPrefill(WorkoutSetValues(weight: 22.5, reps: 12))

        #expect(viewModel.weightText == "49.6")
        #expect(viewModel.repsText == "12")
        #expect(viewModel.selectedRPE == nil)
    }

    @Test func changingWeightUnitConvertsValidCurrentDraftText() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightText = "22.5"
        viewModel.weightUnit = .pounds

        #expect(viewModel.weightText == "49.6")
        #expect(viewModel.parsedWeight == 49.6)

        viewModel.weightUnit = .kilograms

        #expect(viewModel.weightText == "22.5")
    }

    @Test func changingWeightUnitLeavesInvalidDraftTextAlone() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightText = "bad"
        viewModel.weightUnit = .pounds

        #expect(viewModel.weightText == "bad")
        #expect(viewModel.parsedWeight == nil)
        #expect(viewModel.parsedWeightKilograms == nil)
    }

    @Test func sidePromptBalanceAndCompletionGateReflectUnilateralCounts() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightText = "20"
        viewModel.repsText = "10"

        #expect(viewModel.sidePrompt(isUnilateral: false, leftCount: 2, rightCount: 1) == nil)
        #expect(viewModel.sidePrompt(isUnilateral: true, leftCount: 2, rightCount: 1) == "上一组左侧已完成，请完成右侧")
        #expect(viewModel.sidePrompt(isUnilateral: true, leftCount: 1, rightCount: 2) == "上一组右侧已完成，请完成左侧")
        #expect(viewModel.sidePrompt(isUnilateral: true, leftCount: 1, rightCount: 1) == nil)

        viewModel.selectedSide = .left
        #expect(viewModel.selectedSideMatchesBalance(isUnilateral: false, leftCount: 2, rightCount: 1))
        #expect(viewModel.selectedSideMatchesBalance(isUnilateral: true, leftCount: 2, rightCount: 1) == false)
        #expect(viewModel.canCompleteSet(sessionEnded: false, isUnilateral: true, leftCount: 2, rightCount: 1) == false)

        viewModel.selectedSide = .right
        #expect(viewModel.selectedSideMatchesBalance(isUnilateral: true, leftCount: 2, rightCount: 1))
        #expect(viewModel.canCompleteSet(sessionEnded: false, isUnilateral: true, leftCount: 2, rightCount: 1))
        #expect(viewModel.canCompleteSet(sessionEnded: true, isUnilateral: true, leftCount: 2, rightCount: 1) == false)

        viewModel.weightText = ""
        #expect(viewModel.canCompleteSet(sessionEnded: false, isUnilateral: true, leftCount: 2, rightCount: 1) == false)

        viewModel.weightText = "20"
        viewModel.repsText = "0"
        #expect(viewModel.canCompleteSet(sessionEnded: false, isUnilateral: true, leftCount: 2, rightCount: 1) == false)
    }

    @Test func completionGateAcceptsValidWeightInSelectedUnit() {
        let viewModel = ExerciseLoggingViewModel()

        viewModel.weightUnit = .pounds
        viewModel.weightText = "44.1"
        viewModel.repsText = "10"
        viewModel.selectedSide = .right

        #expect(viewModel.canCompleteSet(sessionEnded: false, isUnilateral: true, leftCount: 2, rightCount: 1))
    }

    @Test func completionTitleUsesExerciseAndSelectedSide() {
        let viewModel = ExerciseLoggingViewModel()

        #expect(viewModel.completionButtonTitle(isUnilateral: false) == "完成本组 · 开始计时")
        #expect(viewModel.currentSide(isUnilateral: false) == nil)

        viewModel.selectedSide = .left
        #expect(viewModel.completionButtonTitle(isUnilateral: true) == "完成左侧")
        #expect(viewModel.currentSide(isUnilateral: true) == .left)

        viewModel.selectedSide = .right
        #expect(viewModel.completionButtonTitle(isUnilateral: true) == "完成右侧 · 开始计时")
        #expect(viewModel.currentSide(isUnilateral: true) == .right)
    }

    @Test func sortedSetsUsesCompletedAtThenSetIndex() {
        let viewModel = ExerciseLoggingViewModel()
        let firstAtSameTime = WorkoutSet(
            exerciseNameSnapshot: "Row",
            setIndex: 1,
            completedAt: Date(timeIntervalSince1970: 200)
        )
        let secondAtSameTime = WorkoutSet(
            exerciseNameSnapshot: "Row",
            setIndex: 2,
            completedAt: Date(timeIntervalSince1970: 200)
        )
        let earlierSet = WorkoutSet(
            exerciseNameSnapshot: "Row",
            setIndex: 3,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        let laterSet = WorkoutSet(
            exerciseNameSnapshot: "Row",
            setIndex: 1,
            completedAt: Date(timeIntervalSince1970: 300)
        )

        let sortedSets = viewModel.sortedSets([
            laterSet,
            secondAtSameTime,
            earlierSet,
            firstAtSameTime,
        ])

        #expect(sortedSets.map(\.completedAt) == [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 300),
        ])
        #expect(sortedSets.map(\.setIndex) == [3, 1, 2, 1])
    }
}
