import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct WatchTrainingStateMessageTests {
    @Test func requestMessageRoundTripsThroughPropertyList() throws {
        let sentAt: TimeInterval = 1_800_000_000
        let message = WatchTrainingStateMessage.request(
            requestID: "request-1",
            sentAt: sentAt
        )

        let decoded = try WatchTrainingStateMessage(propertyList: message.propertyList)

        #expect(decoded == message)
        #expect(decoded.propertyList["schemaVersion"] as? Int == 1)
        #expect(decoded.propertyList["kind"] as? String == "trainingState.request")
        #expect(decoded.propertyList["isTraining"] == nil)
    }

    @Test func responseAndUpdateMessagesRoundTripWithTrainingState() throws {
        let sentAt: TimeInterval = 1_800_000_001
        let response = WatchTrainingStateMessage.response(
            requestID: "request-2",
            sentAt: sentAt,
            isTraining: true
        )
        let update = WatchTrainingStateMessage.update(
            requestID: "update-1",
            sentAt: sentAt,
            isTraining: false
        )

        #expect(try WatchTrainingStateMessage(propertyList: response.propertyList) == response)
        #expect(try WatchTrainingStateMessage(propertyList: update.propertyList) == update)
        #expect(response.propertyList["kind"] as? String == "trainingState.response")
        #expect(update.propertyList["kind"] as? String == "trainingState.update")
    }

    @Test func invalidFieldsFailDecoding() {
        expectParseError(.invalidSchemaVersion) {
            try WatchTrainingStateMessage(propertyList: [
                "schemaVersion": 2,
                "kind": "trainingState.request",
                "requestID": "request-1",
                "sentAt": TimeInterval(1_800_000_000),
            ])
        }

        expectParseError(.invalidKind) {
            try WatchTrainingStateMessage(propertyList: [
                "schemaVersion": 1,
                "kind": "trainingState.unknown",
                "requestID": "request-1",
                "sentAt": TimeInterval(1_800_000_000),
            ])
        }

        expectParseError(.invalidIsTraining) {
            try WatchTrainingStateMessage(propertyList: [
                "schemaVersion": 1,
                "kind": "trainingState.response",
                "requestID": "request-1",
                "sentAt": TimeInterval(1_800_000_000),
            ])
        }

        expectParseError(.unexpectedIsTraining) {
            try WatchTrainingStateMessage(propertyList: [
                "schemaVersion": 1,
                "kind": "trainingState.request",
                "requestID": "request-1",
                "sentAt": TimeInterval(1_800_000_000),
                "isTraining": true,
            ])
        }
    }

    private func expectParseError(
        _ expectedError: WatchTrainingStateMessage.ParseError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected \(expectedError)")
        } catch let error as WatchTrainingStateMessage.ParseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@MainActor
struct PhoneTrainingStateSourceTests {
    @Test func sourceReturnsFalseWithoutOpenSession() throws {
        let context = try makeInMemoryContext()

        #expect(try PhoneTrainingStateSource.live.isTraining(context) == false)
    }

    @Test func sourceReturnsTrueWithOpenSession() throws {
        let context = try makeInMemoryContext()
        let template = Template(name: "Push A", stableID: "template-push-a")
        context.insert(template)
        try context.save()

        _ = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        #expect(try PhoneTrainingStateSource.live.isTraining(context) == true)
    }

    @Test func sourceReturnsFalseAfterEndAndDiscard() throws {
        let context = try makeInMemoryContext()
        let template = Template(name: "Push A", stableID: "template-push-a")
        context.insert(template)
        try context.save()

        let endedSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        try WorkoutSessionLifecycle.end(endedSession, in: context)

        #expect(try PhoneTrainingStateSource.live.isTraining(context) == false)

        let discardedSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        try WorkoutSessionLifecycle.discard(discardedSession, in: context)

        #expect(try PhoneTrainingStateSource.live.isTraining(context) == false)
    }
}

@MainActor
struct PhoneWatchTrainingStateSyncTests {
    @Test func refreshPublishesCurrentTrainingStateAsApplicationContext() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in true },
            now: { Date(timeIntervalSince1970: 1_800_000_010) },
            makeRequestID: { "update-request" }
        )

        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        #expect(transport.activateCount == 1)
        #expect(transport.applicationContexts.count == 1)

        let update = try #require(try transport.latestTrainingStateMessage())
        #expect(update.kind == .update)
        #expect(update.requestID == "update-request")
        #expect(update.isTraining == true)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func activationSuccessPublishesLatestTrainingState() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        var isTraining = false
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in isTraining },
            now: { Date(timeIntervalSince1970: 1_800_000_012) },
            makeRequestID: { "activation-update" }
        )

        sync.bind(modelContext: context)
        sync.activate()
        isTraining = true
        transport.completeActivationSuccessfully()

        #expect(transport.applicationContexts.count == 1)
        #expect(transport.updateApplicationContextCallCount == 1)

        let update = try #require(try transport.latestTrainingStateMessage())
        #expect(update.kind == .update)
        #expect(update.requestID == "activation-update")
        #expect(update.isTraining == true)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func activationSuccessWithoutModelContextDoesNotPublishOrDiagnose() {
        let transport = FakePhoneWatchTrainingStateTransport()
        var sourceCallCount = 0
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in
                sourceCallCount += 1
                return true
            }
        )

        sync.activate()
        transport.completeActivationSuccessfully()

        #expect(sourceCallCount == 0)
        #expect(transport.applicationContexts.isEmpty)
        #expect(transport.updateApplicationContextCallCount == 0)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func activationSuccessPublishErrorIsDiagnosticAndDoesNotAutomaticallyRetry() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        transport.updateApplicationContextError = SentinelWatchSyncError.updateFailed
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in true }
        )

        sync.bind(modelContext: context)
        sync.activate()
        transport.completeActivationSuccessfully()

        #expect(transport.applicationContexts.isEmpty)
        #expect(transport.updateApplicationContextCallCount == 1)
        #expect(sync.latestDiagnostic == .publishFailed("Injected update failure"))

        transport.updateApplicationContextError = nil

        #expect(transport.applicationContexts.isEmpty)
        #expect(transport.updateApplicationContextCallCount == 1)
        #expect(sync.latestDiagnostic == .publishFailed("Injected update failure"))
    }

    @Test func requestReplyEchoesRequestIDAndCurrentTrainingState() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in true },
            now: { Date(timeIntervalSince1970: 1_800_000_011) }
        )
        let request = WatchTrainingStateMessage.request(
            requestID: "watch-request",
            sentAt: 1_800_000_000
        )

        sync.bind(modelContext: context)
        sync.activate()

        let reply = try #require(transport.receive(request.propertyList))
        let response = try WatchTrainingStateMessage(propertyList: reply)

        #expect(response.kind == .response)
        #expect(response.requestID == "watch-request")
        #expect(response.isTraining == true)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func publishErrorIsDiagnosticAndDoesNotThrow() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        transport.updateApplicationContextError = SentinelWatchSyncError.updateFailed
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in false }
        )

        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        #expect(transport.applicationContexts.isEmpty)
        #expect(sync.latestDiagnostic == .publishFailed("Injected update failure"))
    }

    @Test func requestSourceErrorIsDiagnosticAndDoesNotReply() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in
                throw SentinelWatchSyncError.sourceFailed
            }
        )
        let request = WatchTrainingStateMessage.request(
            requestID: "watch-request",
            sentAt: 1_800_000_000
        )

        sync.bind(modelContext: context)
        sync.activate()

        #expect(transport.receive(request.propertyList) == nil)
        #expect(sync.latestDiagnostic == .sourceFailed("Injected source failure"))
    }

    @Test func invalidRequestIsDiagnosticAndDoesNotReply() {
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(transport: transport)

        sync.activate()

        #expect(transport.receive(["schemaVersion": 1]) == nil)
        #expect(sync.latestDiagnostic == .invalidRequest("invalidKind"))
    }
}

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let container = try DaaiZekBroSchema.makeModelContainer(isStoredInMemoryOnly: true)

    return ModelContext(container)
}

@MainActor
private final class FakePhoneWatchTrainingStateTransport: PhoneWatchTrainingStateTransport {
    private var incomingMessageHandler: (@MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void)?
    private var activationSuccessHandler: (@MainActor () -> Void)?
    private(set) var activateCount = 0
    private(set) var updateApplicationContextCallCount = 0
    private(set) var applicationContexts: [[String: Any]] = []
    var updateApplicationContextError: Error?

    func setIncomingMessageHandler(
        _ handler: @escaping @MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void
    ) {
        incomingMessageHandler = handler
    }

    func setDiagnosticHandler(_ handler: @escaping @MainActor (String) -> Void) {}

    func setActivationSuccessHandler(_ handler: @escaping @MainActor () -> Void) {
        activationSuccessHandler = handler
    }

    func activate() {
        activateCount += 1
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        updateApplicationContextCallCount += 1

        if let updateApplicationContextError {
            throw updateApplicationContextError
        }

        applicationContexts.append(applicationContext)
    }

    func receive(_ message: [String: Any]) -> [String: Any]? {
        var reply: [String: Any]?
        incomingMessageHandler?(message) { response in
            reply = response
        }

        return reply
    }

    func completeActivationSuccessfully() {
        activationSuccessHandler?()
    }

    func latestTrainingStateMessage() throws -> WatchTrainingStateMessage? {
        guard let applicationContext = applicationContexts.last else {
            return nil
        }

        return try WatchTrainingStateMessage(propertyList: applicationContext)
    }
}

private enum SentinelWatchSyncError: LocalizedError {
    case updateFailed
    case sourceFailed

    var errorDescription: String? {
        switch self {
        case .updateFailed:
            "Injected update failure"
        case .sourceFailed:
            "Injected source failure"
        }
    }
}
