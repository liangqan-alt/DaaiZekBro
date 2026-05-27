import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct SchemaSingleSourceTests {
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

    @Test func sharedSchemaCreatesInMemoryContainer() throws {
        let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)
        let context = ModelContext(container)
        let exercise = Exercise(name: "Schema Smoke")

        context.insert(exercise)
        try context.save()

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.map(\.name) == ["Schema Smoke"])
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

        context.insert(Template(name: "Schema File Smoke"))
        try context.save()

        let templates = try context.fetch(FetchDescriptor<Template>())
        #expect(templates.map(\.name) == ["Schema File Smoke"])
    }
}
