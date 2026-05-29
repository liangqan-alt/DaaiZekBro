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

        let loader = AppModelContainerLoader {
            try DaaiZekBroSchema.makeModelContainer(storeURL: copiedStoreURL)
        }

        guard case .success(let container) = loader.load() else {
            Issue.record("Expected legacy store to open through the startup loader")
            return
        }

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

    private static func legacyStoreURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["DZ_LEGACY_STORE_URL"]
            ?? environment["TEST_RUNNER_DZ_LEGACY_STORE_URL"]
        else {
            return nil
        }

        return URL(fileURLWithPath: path)
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
}
