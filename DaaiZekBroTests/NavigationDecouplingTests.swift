import Foundation
import Testing

struct NavigationDecouplingTests {
    @Test func trainingScheduleViewDoesNotDependOnAppLevelPath() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = sourceRoot
            .appending(path: "DaaiZekBro")
            .appending(path: "Features")
            .appending(path: "TrainingSchedule")
            .appending(path: "TrainingScheduleView.swift")
        let contents = try String(contentsOf: fileURL)
        let forbiddenTokens = [
            "AppRoute",
            "Binding<[AppRoute]>",
            "usesExternalPath",
            "path.append(",
            "path.removeAll(",
            "path.removeLast(",
        ]

        let violations = forbiddenTokens.filter { contents.contains($0) }

        #expect(
            violations.isEmpty,
            "TrainingScheduleView should not directly depend on app-level navigation path: \(violations)"
        )
    }
}
