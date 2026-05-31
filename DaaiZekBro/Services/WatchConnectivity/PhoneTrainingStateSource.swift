import Foundation
import SwiftData

@MainActor
struct PhoneTrainingStateSource {
    var isTraining: @MainActor (ModelContext) throws -> Bool

    static let live = PhoneTrainingStateSource { context in
        try WorkoutSessionLifecycle.currentOpenSession(in: context) != nil
    }
}
