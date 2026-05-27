import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct AppStartupTests {
    @Test func modelContainerLoaderReturnsSuccessWhenFactoryCreatesContainer() throws {
        let loader = AppModelContainerLoader {
            try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)
        }

        guard case .success(let container) = loader.load() else {
            Issue.record("Expected startup loader to return a ModelContainer")
            return
        }

        let context = ModelContext(container)
        context.insert(Exercise(name: "Startup Smoke"))
        try context.save()

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(exercises.map(\.name) == ["Startup Smoke"])
    }

    @Test func modelContainerLoaderReturnsDiagnosticFailureWhenFactoryThrows() {
        let loader = AppModelContainerLoader {
            throw SentinelContainerError()
        }

        guard case .failure(let failure) = loader.load() else {
            Issue.record("Expected startup loader to return a diagnostic failure")
            return
        }

        #expect(failure.title == "无法打开本地数据")
        #expect(failure.message.contains("没有被自动擦除"))
        #expect(failure.diagnosticMessage.contains("Injected container failure"))
    }
}

private struct SentinelContainerError: LocalizedError {
    var errorDescription: String? {
        "Injected container failure for startup tests"
    }
}
