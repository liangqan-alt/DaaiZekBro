import Foundation

enum AppRoute: Hashable {
    case currentWorkout(sessionID: UUID)
    case exerciseLogging(sessionID: UUID, exerciseName: String)
    case settings
}
