import Foundation
import SwiftData

enum AppRoute: Hashable {
    case currentWorkout(sessionID: UUID)
    case exerciseLogging(sessionID: UUID, exerciseName: String)
    case templateEdit(templateID: PersistentIdentifier)
    case trainingSchedule
    case settings
}
