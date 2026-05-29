import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct LegacyStoreCompatibilityTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["DZ_LEGACY_STORE_URL"] != nil
            || ProcessInfo.processInfo.environment["TEST_RUNNER_DZ_LEGACY_STORE_URL"] != nil,
        "Set DZ_LEGACY_STORE_URL to run legacy store compatibility validation"
    ))
    func legacyStoreOpensThroughStartupLoaderAndHistoryIsReadable() throws {
        let sourceStoreURL = try #require(Self.legacyStoreURL())
        let copiedStoreURL = try copyStoreFiles(from: sourceStoreURL)
        defer { removeCopiedStoreFiles(at: copiedStoreURL) }

        let container = try loadModelContainer(at: copiedStoreURL)
        let context = ModelContext(container)
        try SeedData.writeAndDedup(in: context)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let historySections = WorkoutHistoryData.sections(
            sessions: sessions,
            sets: sets,
            now: Date(timeIntervalSince1970: 1_779_910_200),
            calendar: calendar
        )

        #expect(containerUsesSharedMigrationPlan(container))
        #expect(sessions.isEmpty == false)
        #expect(sets.isEmpty == false)
        #expect(sets.contains { $0.session != nil })
        #expect(historySections.flatMap(\.rows).isEmpty == false)
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["DZ_LEGACY_STORE_URL"] != nil
            || ProcessInfo.processInfo.environment["TEST_RUNNER_DZ_LEGACY_STORE_URL"] != nil,
        "Set DZ_LEGACY_STORE_URL to run legacy store compatibility validation"
    ))
    func legacyStoreMigratesWorkoutSetCascadeSemantics() throws {
        let sourceStoreURL = try #require(Self.legacyStoreURL())

        let cascadeStoreURL = try copyStoreFiles(from: sourceStoreURL)
        defer { removeCopiedStoreFiles(at: cascadeStoreURL) }

        do {
            let container = try loadModelContainer(at: cascadeStoreURL)
            let context = ModelContext(container)
            let preMigrationData = try preMigrationSessionWithRelatedSets(in: context)
            let sessionID = preMigrationData.session.id
            let relatedSetIDs = preMigrationData.sets.map(\.persistentModelID)

            #expect(containerUsesSharedMigrationPlan(container))
            #expect(preMigrationData.sets.isEmpty == false)
            #expect(preMigrationData.sets.allSatisfy { $0.session?.id == sessionID })

            context.delete(preMigrationData.session)
            try context.save()

            let remainingSessions = try fetchSessions(in: context)
            let remainingSets = try fetchSets(in: context)

            #expect(remainingSessions.contains { $0.id == sessionID } == false)
            #expect(remainingSets.allSatisfy { $0.session?.id != sessionID })
            #expect(remainingSets.allSatisfy { relatedSetIDs.contains($0.persistentModelID) == false })
        }

        let deleteSetStoreURL = try copyStoreFiles(from: sourceStoreURL)
        defer { removeCopiedStoreFiles(at: deleteSetStoreURL) }

        do {
            let container = try loadModelContainer(at: deleteSetStoreURL)
            let context = ModelContext(container)
            let preMigrationData = try preMigrationSessionWithRelatedSets(in: context)
            let sessionID = preMigrationData.session.id
            let set = try #require(preMigrationData.sets.first)
            let setID = set.persistentModelID

            context.delete(set)
            try context.save()

            let remainingSessions = try fetchSessions(in: context)
            let remainingSets = try fetchSets(in: context)

            #expect(remainingSessions.contains { $0.id == sessionID })
            #expect(remainingSets.contains { $0.persistentModelID == setID } == false)
        }
    }

    private static func legacyStoreURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["DZ_LEGACY_STORE_URL"]
            ?? environment["TEST_RUNNER_DZ_LEGACY_STORE_URL"]
        else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private func loadModelContainer(at copiedStoreURL: URL) throws -> ModelContainer {
        let loader = AppModelContainerLoader {
            try DaaiZekBroSchema.makeModelContainer(storeURL: copiedStoreURL)
        }

        switch loader.load() {
        case .success(let container):
            return container
        case .failure(let failure):
            throw LegacyStoreCompatibilityTestError.modelContainerStartupFailed(failure.diagnosticMessage)
        }
    }

    private func preMigrationSessionWithRelatedSets(
        in context: ModelContext
    ) throws -> (session: WorkoutSession, sets: [WorkoutSet]) {
        let sessions = try fetchSessions(in: context)
        let sets = try fetchSets(in: context)

        for session in sessions {
            let relatedSets = sets.filter { $0.session?.id == session.id }

            if relatedSets.isEmpty == false {
                return (session, relatedSets)
            }
        }

        throw LegacyStoreCompatibilityTestError.missingPreMigrationSessionWithRelatedSets
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
                sortBy: [
                    SortDescriptor(\WorkoutSet.completedAt),
                    SortDescriptor(\WorkoutSet.setIndex),
                ]
            )
        )
    }

    private func copyStoreFiles(from sourceStoreURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let destinationDirectory = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        let destinationStoreURL = destinationDirectory.appending(path: sourceStoreURL.lastPathComponent)

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try #require(fileManager.fileExists(atPath: sourceStoreURL.path()))

        for sourceFileURL in storeFileURLs(for: sourceStoreURL) where fileManager.fileExists(atPath: sourceFileURL.path()) {
            let destinationFileURL = destinationDirectory.appending(path: sourceFileURL.lastPathComponent)
            try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
        }

        return destinationStoreURL
    }

    private func removeCopiedStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default

        for fileURL in storeFileURLs(for: storeURL) {
            try? fileManager.removeItem(at: fileURL)
        }

        try? fileManager.removeItem(at: storeURL.deletingLastPathComponent())
    }

    private func storeFileURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            storeURL.deletingPathExtension().appendingPathExtension("store-shm"),
            storeURL.deletingPathExtension().appendingPathExtension("store-wal"),
        ]
    }

    private func containerUsesSharedMigrationPlan(_ container: ModelContainer) -> Bool {
        guard let migrationPlan = container.migrationPlan else {
            return false
        }

        return ObjectIdentifier(migrationPlan) == ObjectIdentifier(DaaiZekBroMigrationPlan.self)
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw LegacyStoreCompatibilityTestError.missingTimeZone(identifier)
        }

        return timeZone
    }
}

private enum LegacyStoreCompatibilityTestError: Error {
    case missingTimeZone(String)
    case missingPreMigrationSessionWithRelatedSets
    case modelContainerStartupFailed(String)
}
