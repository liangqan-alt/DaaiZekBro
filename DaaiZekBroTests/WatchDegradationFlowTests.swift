import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct WatchDegradationFlowTests {
    @Test func startingWorkoutSurvivesBestEffortWatchRefreshFailure() throws {
        let context = try makeInMemoryContext()
        let template = try makeTemplate(
            name: "Push A",
            stableID: "template-push-a",
            exercises: [
                Exercise(name: "Bench Press", defaultRestSeconds: 120, isUnilateral: false, weightUnit: .kilograms),
            ],
            in: context
        )
        let transport = WatchDegradationTransport()
        let sync = makeSync(transport: transport)
        let startedAt = try date(2026, 1, 1, 12, 0, 0)

        let result = try WorkoutStartFlow.startOrConflict(
            for: template,
            in: context,
            startedAt: startedAt,
            timeZone: try requiredTimeZone()
        )

        guard case .started(let session) = result else {
            Issue.record("Expected a started session")
            return
        }

        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        let openSession = try #require(try WorkoutSessionLifecycle.currentOpenSession(in: context))
        #expect(openSession.id == session.id)
        #expect(openSession.templateNameSnapshot == "Push A")
        #expect(openSession.templateStableIDSnapshot == "template-push-a")
        #expect(openSession.startedAt == startedAt)
        #expect(openSession.endedAt == nil)
        #expect(try fetchSessions(in: context).count == 1)
        #expect(transport.updateApplicationContextCallCount == 1)
        #expect(sync.latestDiagnostic == .transportUnavailable)
    }

    @Test func recordedIPhoneSetSurvivesBestEffortWatchRefreshFailure() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Accessory",
            exercises: [
                Exercise(name: "Lateral Raise", defaultRestSeconds: 60, isUnilateral: true, weightUnit: .kilograms),
            ],
            in: context
        )
        let transport = WatchDegradationTransport()
        let sync = makeSync(transport: transport)
        let completedAt = try date(2026, 1, 1, 12, 5, 0)

        let savedSet = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            weight: 12.5,
            reps: 10,
            rpe: 8,
            side: .left,
            completedAt: completedAt,
            in: context
        )

        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        let savedSets = try WorkoutSetLogging.setsForExercise(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        )
        let set = try #require(savedSets.first)

        #expect(savedSets.count == 1)
        #expect(set.persistentModelID == savedSet.persistentModelID)
        #expect(set.exerciseNameSnapshot == "Lateral Raise")
        #expect(set.exerciseOrderIndex == 0)
        #expect(set.setIndex == 1)
        #expect(set.weight == 12.5)
        #expect(set.reps == 10)
        #expect(set.rpe == 8)
        #expect(set.side == .left)
        #expect(set.completedAt == completedAt)
        #expect(transport.updateApplicationContextCallCount == 1)
        #expect(sync.latestDiagnostic == .transportUnavailable)
    }

    @Test func endedWorkoutSurvivesBestEffortWatchRefreshFailureAndRemainsInHistory() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Push A",
            exercises: [
                Exercise(name: "Bench Press", defaultRestSeconds: 120, isUnilateral: false, weightUnit: .kilograms),
            ],
            in: context
        )
        let completedAt = try date(2026, 1, 1, 12, 5, 0)
        let endedAt = try date(2026, 1, 1, 12, 45, 0)
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            weight: 80,
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: completedAt,
            in: context
        )
        let transport = WatchDegradationTransport()
        let sync = makeSync(transport: transport)

        try WorkoutSessionLifecycle.end(session, in: context, endedAt: endedAt)
        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        let sessions = try fetchSessions(in: context)
        let sets = try fetchSets(in: context)
        let sections = WorkoutHistoryData.sections(
            sessions: sessions,
            sets: sets,
            now: endedAt,
            calendar: try gregorianCalendar()
        )

        #expect(try WorkoutSessionLifecycle.currentOpenSession(in: context) == nil)
        #expect(sessions.count == 1)
        #expect(sessions[0].id == session.id)
        #expect(sessions[0].endedAt == endedAt)
        #expect(sets.count == 1)
        #expect(sections.count == 1)
        #expect(sections[0].rows.map(\.id) == [session.id])
        #expect(sections[0].rows[0].summary.templateName == "Push A")
        #expect(sections[0].rows[0].summary.setCount == 1)
        #expect(transport.updateApplicationContextCallCount == 1)
        #expect(sync.latestDiagnostic == .transportUnavailable)
    }

    @Test func iPhoneMainFlowDoesNotReadWatchDiagnosticsForUserFacingDegradation() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let checkedDirectories = [
            "DaaiZekBro/App",
            "DaaiZekBro/Features",
        ]
        let forbiddenTokens = [
            "latestDiagnostic",
            "DiagnosticState",
            "transportUnavailable",
            "publishFailed",
            "activationFailed",
        ]
        var violations: [String] = []

        for directory in checkedDirectories {
            let directoryURL = sourceRoot.appending(path: directory)
            let filePaths = try FileManager.default.subpathsOfDirectory(atPath: directoryURL.path())

            for filePath in filePaths where filePath.hasSuffix(".swift") {
                let fileURL = directoryURL.appending(path: filePath)
                let contents = try String(contentsOf: fileURL)
                let matchedTokens = forbiddenTokens.filter { contents.contains($0) }

                if matchedTokens.isEmpty == false {
                    violations.append("\(directory)/\(filePath): \(matchedTokens.joined(separator: ", "))")
                }
            }
        }

        #expect(
            violations.isEmpty,
            "iPhone main flow should not surface Watch diagnostics as blocking degradation UI: \(violations)"
        )
    }

    private func requiredTimeZone() throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: "Asia/Shanghai") else {
            throw WatchDegradationFlowTestError.missingTimeZone("Asia/Shanghai")
        }

        return timeZone
    }

    private func gregorianCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try requiredTimeZone()
        return calendar
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

        return ModelContext(container)
    }

    private func makeSync(transport: WatchDegradationTransport) -> PhoneWatchTrainingStateSync {
        PhoneWatchTrainingStateSync(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_800_000_200) },
            makeRequestID: { "watch-degradation-update" }
        )
    }

    private func makeSession(
        templateName: String,
        exercises: [Exercise],
        in context: ModelContext
    ) throws -> WorkoutSession {
        let template = try makeTemplate(
            name: templateName,
            stableID: "template-\(templateName.lowercased().replacingOccurrences(of: " ", with: "-"))",
            exercises: exercises,
            in: context
        )

        return try WorkoutSessionLifecycle.createSession(
            for: template,
            in: context,
            startedAt: try date(2026, 1, 1, 12, 0, 0),
            timeZone: try requiredTimeZone()
        )
    }

    private func makeTemplate(
        name: String,
        stableID: String,
        exercises: [Exercise],
        in context: ModelContext
    ) throws -> Template {
        let template = Template(name: name, stableID: stableID)
        context.insert(template)

        for (index, exercise) in exercises.enumerated() {
            context.insert(exercise)
            context.insert(TemplateExercise(template: template, exercise: exercise, orderIndex: index))
        }

        try context.save()

        return template
    }

    private func fetchSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(
            FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\WorkoutSession.startedAt)]
            )
        )
    }

    private func fetchSets(in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(
            FetchDescriptor<WorkoutSet>(
                sortBy: [SortDescriptor(\WorkoutSet.completedAt)]
            )
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int
    ) throws -> Date {
        let timeZone = try requiredTimeZone()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        guard let date = components.date else {
            throw WatchDegradationFlowTestError.invalidDate
        }

        return date
    }
}

@MainActor
private final class WatchDegradationTransport: PhoneWatchTrainingStateTransport {
    private(set) var updateApplicationContextCallCount = 0

    func setIncomingMessageHandler(
        _ handler: @escaping @MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void
    ) {}

    func setDiagnosticHandler(_ handler: @escaping @MainActor (String) -> Void) {}

    func setActivationSuccessHandler(_ handler: @escaping @MainActor () -> Void) {}

    func activate() {}

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        updateApplicationContextCallCount += 1
        throw PhoneWatchTrainingStateSync.DiagnosticState.transportUnavailable
    }
}

private enum WatchDegradationFlowTestError: Error {
    case invalidDate
    case missingTimeZone(String)
}
