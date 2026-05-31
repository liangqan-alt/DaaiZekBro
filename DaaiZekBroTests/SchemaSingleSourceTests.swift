import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct SchemaSingleSourceTests {
    private let expectedModelTypes: [any PersistentModel.Type] = [
        Exercise.self,
        Template.self,
        TemplateExercise.self,
        WorkoutSession.self,
        TrainingCycle.self,
        TrainingCycleSlot.self,
        TrainingDayOverride.self,
        WorkoutSessionExerciseSnapshot.self,
        WorkoutSet.self,
        WatchSetSubmissionRecord.self,
    ]
    private let expectedModelNames = [
        "Exercise",
        "Template",
        "TemplateExercise",
        "WorkoutSession",
        "TrainingCycle",
        "TrainingCycleSlot",
        "TrainingDayOverride",
        "WorkoutSessionExerciseSnapshot",
        "WorkoutSet",
        "WatchSetSubmissionRecord",
    ]
    private let expectedPreLedgerModelNames = [
        "Exercise",
        "Template",
        "TemplateExercise",
        "WorkoutSession",
        "TrainingCycle",
        "TrainingCycleSlot",
        "TrainingDayOverride",
        "WorkoutSessionExerciseSnapshot",
        "WorkoutSet",
    ]

    @Test func schemaModelListIsNotRepeatedInAppOrTests() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let checkedDirectories = ["DaaiZekBro", "DaaiZekBroTests"]
        let inlineSchemaPattern = try #require(try? Regex("Schema\\s*\\(\\s*\\["))
        let inlinePreviewPattern = try #require(try? Regex("\\.modelContainer\\s*\\(\\s*for:\\s*\\["))
        var violations: [String] = []

        for directory in checkedDirectories {
            let directoryURL = sourceRoot.appending(path: directory)
            let filePaths = try FileManager.default.subpathsOfDirectory(atPath: directoryURL.path())

            for filePath in filePaths where filePath.hasSuffix(".swift") && filePath != "SchemaSingleSourceTests.swift" {
                let fileURL = directoryURL.appending(path: filePath)
                let contents = try String(contentsOf: fileURL)

                if contents.contains(inlineSchemaPattern) || contents.contains(inlinePreviewPattern) {
                    violations.append("\(directory)/\(filePath)")
                }
            }
        }

        #expect(violations.isEmpty, "Schema model lists should only be declared in DaaiZekBroSchema: \(violations)")
    }

    @Test func schemaModelListOrderMatchesCurrentStoreContract() {
        #expect(typeIdentifiers(DaaiZekBroSchema.modelTypes) == typeIdentifiers(expectedModelTypes))
        #expect(modelNames(DaaiZekBroSchemaV1.models) == expectedPreLedgerModelNames)
        #expect(modelNames(DaaiZekBroSchemaV2.models) == expectedPreLedgerModelNames)
        #expect(modelNames(DaaiZekBroSchemaV3.models) == expectedPreLedgerModelNames)
        #expect(typeIdentifiers(DaaiZekBroSchemaV4.models) == typeIdentifiers(expectedModelTypes))
        #expect(typeIdentifiers(DaaiZekBroSchema.modelTypes) == typeIdentifiers(DaaiZekBroSchemaV4.models))
    }

    @Test func migrationPlanDeclaresCurrentSchemaWithLightweightStages() {
        #expect(
            DaaiZekBroMigrationPlan.schemas.map { ObjectIdentifier($0) } == [
                ObjectIdentifier(DaaiZekBroSchemaV1.self),
                ObjectIdentifier(DaaiZekBroSchemaV2.self),
                ObjectIdentifier(DaaiZekBroSchemaV3.self),
                ObjectIdentifier(DaaiZekBroSchemaV4.self),
            ]
        )
        #expect(DaaiZekBroMigrationPlan.stages.count == 3)

        assertLightweightStage(
            DaaiZekBroMigrationPlan.stages[0],
            from: DaaiZekBroSchemaV1.self,
            to: DaaiZekBroSchemaV2.self
        )
        assertLightweightStage(
            DaaiZekBroMigrationPlan.stages[1],
            from: DaaiZekBroSchemaV2.self,
            to: DaaiZekBroSchemaV3.self
        )
        assertLightweightStage(
            DaaiZekBroMigrationPlan.stages[2],
            from: DaaiZekBroSchemaV3.self,
            to: DaaiZekBroSchemaV4.self
        )
    }

    @Test func sharedSchemaCreatesInMemoryContainer() throws {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let exercise = Exercise(name: "Schema Smoke")

        #expect(containerUsesSharedMigrationPlan(container))

        context.insert(exercise)
        try context.save()

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.map(\.name) == ["Schema Smoke"])
        #expect(exercises.map(\.weightUnit) == [.kilograms])

        context.insert(
            WatchSetSubmissionRecord(
                clientSubmissionID: "schema-ledger-smoke",
                originalSessionID: UUID().uuidString,
                exerciseOrderIndex: 0,
                exerciseName: "Schema Smoke",
                weight: 10,
                weightUnit: .kilograms,
                reps: 8,
                rpe: nil,
                completedAt: Date(timeIntervalSince1970: 1_800_000_101),
                submittedAt: Date(timeIntervalSince1970: 1_800_000_100),
                status: .needsUserAction,
                reason: .syncTimeout,
                message: "需要处理",
                savedSetIndex: nil,
                completedSetCount: nil
            )
        )
        try context.save()

        let ledgerEntries = try context.fetch(FetchDescriptor<WatchSetSubmissionRecord>())
        #expect(ledgerEntries.map(\.clientSubmissionID) == ["schema-ledger-smoke"])
        #expect(ledgerEntries.map(\.status) == [.needsUserAction])
    }

    @Test func sharedSchemaCreatesFileBackedContainer() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("store-wal"))
        }

        let container = try DaaiZekBroSchema.makeModelContainer(storeURL: storeURL)
        let context = ModelContext(container)

        #expect(containerUsesSharedMigrationPlan(container))

        context.insert(Template(name: "Schema File Smoke"))
        try context.save()

        let templates = try context.fetch(FetchDescriptor<Template>())
        #expect(templates.map(\.name) == ["Schema File Smoke"])
    }

    @Test func fileBackedContainerReopensCompletedWorkoutHistory() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("store")
        let timeZone = try requiredTimeZone("Asia/Shanghai")
        let startedAt = try date(2026, 5, 28, 9, 0, 0, timeZone: timeZone)
        let sessionID = UUID()
        defer { removeStoreFiles(at: storeURL) }

        do {
            let container = try DaaiZekBroSchema.makeModelContainer(storeURL: storeURL)
            let context = ModelContext(container)
            let exercise = Exercise(name: "Schema Reopen Press")
            let template = Template(name: "Schema Reopen Template", exercises: [exercise])
            let session = WorkoutSession(
                id: sessionID,
                template: template,
                templateNameSnapshot: template.name,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(3_600),
                timezoneIdentifier: timeZone.identifier
            )

            context.insert(exercise)
            context.insert(template)
            context.insert(TemplateExercise(template: template, exercise: exercise, orderIndex: 0))
            context.insert(session)
            context.insert(
                WorkoutSessionExerciseSnapshot(
                    session: session,
                    exercise: exercise,
                    exerciseNameSnapshot: exercise.name,
                    orderIndex: 0
                )
            )
            context.insert(
                WorkoutSet(
                    session: session,
                    exercise: exercise,
                    exerciseNameSnapshot: exercise.name,
                    exerciseOrderIndex: 0,
                    weight: 60,
                    reps: 8,
                    completedAt: startedAt.addingTimeInterval(600)
                )
            )
            try context.save()
        }

        let reopenedContainer = try DaaiZekBroSchema.makeModelContainer(storeURL: storeURL)
        let reopenedContext = ModelContext(reopenedContainer)
        let sessions = try reopenedContext.fetch(FetchDescriptor<WorkoutSession>())
        let sets = try reopenedContext.fetch(FetchDescriptor<WorkoutSet>())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let historySections = WorkoutHistoryData.sections(
            sessions: sessions,
            sets: sets,
            now: startedAt.addingTimeInterval(7_200),
            calendar: calendar
        )

        #expect(containerUsesSharedMigrationPlan(reopenedContainer))
        #expect(sessions.map(\.id) == [sessionID])
        #expect(sets.map { $0.session?.id } == [sessionID])
        #expect(historySections.flatMap(\.rows).map(\.id) == [sessionID])
    }

    @Test func v3FileBackedStoreMigratesToV4LedgerSchema() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("store")
        defer { removeStoreFiles(at: storeURL) }

        do {
            let schema = Schema(versionedSchema: DaaiZekBroSchemaV3.self)
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let exercise = DaaiZekBroSchemaV3.Exercise()
            exercise.name = "V3 Migration Press"
            exercise.weightUnitRawValue = WeightUnit.pounds.rawValue

            context.insert(exercise)
            try context.save()
        }

        let migratedContainer = try DaaiZekBroSchema.makeModelContainer(storeURL: storeURL)
        let migratedContext = ModelContext(migratedContainer)
        let exercises = try migratedContext.fetch(FetchDescriptor<Exercise>())

        #expect(containerUsesSharedMigrationPlan(migratedContainer))
        #expect(exercises.map(\.name) == ["V3 Migration Press"])
        #expect(exercises.map(\.weightUnit) == [.pounds])

        migratedContext.insert(
            WatchSetSubmissionRecord(
                clientSubmissionID: "v4-ledger-after-migration",
                originalSessionID: UUID().uuidString,
                exerciseOrderIndex: 0,
                exerciseName: "V3 Migration Press",
                weight: 100,
                weightUnit: .pounds,
                reps: 8,
                status: .needsUserAction,
                reason: .syncTimeout,
                message: "需要处理"
            )
        )
        try migratedContext.save()

        let ledgerEntries = try migratedContext.fetch(FetchDescriptor<WatchSetSubmissionRecord>())
        #expect(ledgerEntries.map(\.clientSubmissionID) == ["v4-ledger-after-migration"])
    }

    private func typeIdentifiers(_ types: [any PersistentModel.Type]) -> [ObjectIdentifier] {
        types.map { ObjectIdentifier($0) }
    }

    private func modelNames(_ types: [any PersistentModel.Type]) -> [String] {
        types.map { String(describing: $0) }
    }

    private func containerUsesSharedMigrationPlan(_ container: ModelContainer) -> Bool {
        guard let migrationPlan = container.migrationPlan else {
            return false
        }

        return ObjectIdentifier(migrationPlan) == ObjectIdentifier(DaaiZekBroMigrationPlan.self)
    }

    private func assertLightweightStage(
        _ stage: MigrationStage,
        from expectedFromVersion: any VersionedSchema.Type,
        to expectedToVersion: any VersionedSchema.Type
    ) {
        guard case .lightweight(let fromVersion, let toVersion) = stage else {
            Issue.record("Expected migration stage to be lightweight")
            return
        }

        #expect(ObjectIdentifier(fromVersion) == ObjectIdentifier(expectedFromVersion))
        #expect(ObjectIdentifier(toVersion) == ObjectIdentifier(expectedToVersion))
    }

    private func removeStoreFiles(at storeURL: URL) {
        for fileURL in storeFileURLs(for: storeURL) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func storeFileURLs(for storeURL: URL) -> [URL] {
        [
            storeURL,
            storeURL.deletingPathExtension().appendingPathExtension("store-shm"),
            storeURL.deletingPathExtension().appendingPathExtension("store-wal"),
        ]
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int,
        timeZone: TimeZone
    ) throws -> Date {
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
            throw SchemaSingleSourceTestError.invalidDate
        }

        return date
    }

    private func requiredTimeZone(_ identifier: String) throws -> TimeZone {
        guard let timeZone = TimeZone(identifier: identifier) else {
            throw SchemaSingleSourceTestError.missingTimeZone(identifier)
        }

        return timeZone
    }
}

private enum SchemaSingleSourceTestError: Error {
    case invalidDate
    case missingTimeZone(String)
}
