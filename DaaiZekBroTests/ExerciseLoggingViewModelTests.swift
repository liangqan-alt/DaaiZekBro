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
        #expect(viewModel.parsedReps == 8)

        viewModel.weightText = ""
        viewModel.repsText = ""

        #expect(viewModel.parsedWeight == nil)
        #expect(viewModel.parsedReps == nil)

        viewModel.weightText = "-1"
        viewModel.repsText = "0"

        #expect(viewModel.parsedWeight == nil)
        #expect(viewModel.parsedReps == nil)

        viewModel.weightText = "inf"
        viewModel.repsText = "1.5"

        #expect(viewModel.parsedWeight == nil)
        #expect(viewModel.parsedReps == nil)
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
}
