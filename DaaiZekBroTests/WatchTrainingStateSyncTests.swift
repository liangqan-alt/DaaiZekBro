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

    @Test func snapshotMessageRoundTripsThroughPropertyList() throws {
        let snapshot = makeWatchSnapshot()
        let response = WatchTrainingStateMessage.response(
            requestID: "snapshot-request",
            sentAt: 1_800_000_002,
            isTraining: true,
            snapshot: snapshot
        )
        let update = WatchTrainingStateMessage.update(
            requestID: "snapshot-update",
            sentAt: 1_800_000_003,
            isTraining: true,
            snapshot: snapshot
        )

        #expect(try WatchTrainingStateMessage(propertyList: response.propertyList) == response)
        #expect(try WatchTrainingStateMessage(propertyList: update.propertyList) == update)
        #expect(try #require(WatchTrainingStateMessage(propertyList: response.propertyList).snapshot) == snapshot)
        #expect(try #require(WatchTrainingStateMessage(propertyList: update.propertyList).snapshot) == snapshot)
    }

    @Test func workoutSnapshotRoundTripsThroughPropertyList() throws {
        let snapshot = makeWatchSnapshot()

        let decoded = try WatchWorkoutSnapshot(propertyList: snapshot.propertyList)

        #expect(decoded == snapshot)
        #expect(decoded.sessionName == "Push A")
        #expect(decoded.exercises.map(\.exerciseOrderIndex) == [0, 1])
        #expect(decoded.exercises.map(\.completedSetCount) == [3, 0])
    }

    @Test func invalidFieldsFailDecoding() {
        expectParseError(.invalidSchemaVersion) {
            _ = try WatchTrainingStateMessage(propertyList: [
                "schemaVersion": 2,
                "kind": "trainingState.request",
                "requestID": "request-1",
                "sentAt": TimeInterval(1_800_000_000),
            ])
        }

        expectParseError(.invalidKind) {
            _ = try WatchTrainingStateMessage(propertyList: [
                "schemaVersion": 1,
                "kind": "trainingState.unknown",
                "requestID": "request-1",
                "sentAt": TimeInterval(1_800_000_000),
            ])
        }

        expectParseError(.invalidIsTraining) {
            _ = try WatchTrainingStateMessage(propertyList: [
                "schemaVersion": 1,
                "kind": "trainingState.response",
                "requestID": "request-1",
                "sentAt": TimeInterval(1_800_000_000),
            ])
        }

        expectParseError(.unexpectedIsTraining) {
            _ = try WatchTrainingStateMessage(propertyList: [
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

    @Test func sourceBuildsCurrentSnapshotAndCountsDuplicateNamesByOrderIndex() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Pull A",
            exercises: [
                Exercise(name: "Cable Row", defaultRestSeconds: 90, isUnilateral: false, weightUnit: .kilograms),
                Exercise(name: "Cable Row", defaultRestSeconds: 120, isUnilateral: true, weightUnit: .pounds),
            ],
            in: context
        )

        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Cable Row",
            weight: 40,
            reps: 10,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            exerciseName: "Cable Row",
            weight: 45,
            reps: 8,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 110),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Cable Row",
            weight: 42.5,
            reps: 9,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 120),
            in: context
        )

        let maybeSnapshot = try PhoneTrainingStateSource.live.currentSnapshot(context)
        let snapshot = try #require(maybeSnapshot)

        #expect(snapshot.sessionID == session.id.uuidString)
        #expect(snapshot.sessionName == "Pull A")
        #expect(snapshot.startedAt == session.startedAt.timeIntervalSince1970)
        #expect(snapshot.exercises.map(\.exerciseOrderIndex) == [0, 1])
        #expect(snapshot.exercises.map(\.name) == ["Cable Row", "Cable Row"])
        #expect(snapshot.exercises.map(\.completedSetCount) == [2, 1])
        #expect(snapshot.exercises.map(\.isUnilateral) == [false, true])
        #expect(snapshot.exercises.map(\.defaultRestSeconds) == [90, 120])
        #expect(snapshot.exercises.map(\.weightUnit) == ["kg", "lb"])
    }

    @Test func sourceReturnsFalseAfterEndAndDiscard() throws {
        let context = try makeInMemoryContext()
        let template = Template(name: "Push A", stableID: "template-push-a")
        context.insert(template)
        try context.save()

        let endedSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        try WorkoutSessionLifecycle.end(endedSession, in: context)

        #expect(try PhoneTrainingStateSource.live.isTraining(context) == false)
        #expect(try PhoneTrainingStateSource.live.currentSnapshot(context) == nil)

        let discardedSession = try WorkoutSessionLifecycle.createSession(for: template, in: context)
        try WorkoutSessionLifecycle.discard(discardedSession, in: context)

        #expect(try PhoneTrainingStateSource.live.isTraining(context) == false)
        #expect(try PhoneTrainingStateSource.live.currentSnapshot(context) == nil)
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

    @Test func refreshPublishesNoTrainingWithoutSnapshot() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in false },
            now: { Date(timeIntervalSince1970: 1_800_000_015) },
            makeRequestID: { "idle-update" }
        )

        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        let update = try #require(try transport.latestTrainingStateMessage())
        #expect(update.kind == .update)
        #expect(update.requestID == "idle-update")
        #expect(update.isTraining == false)
        #expect(update.snapshot == nil)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func activationSuccessPublishesLatestTrainingState() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in true },
            now: { Date(timeIntervalSince1970: 1_800_000_012) },
            makeRequestID: { "activation-update" }
        )

        sync.bind(modelContext: context)
        sync.activate()
        transport.completeActivationSuccessfully()

        #expect(transport.applicationContexts.count == 1)
        #expect(transport.updateApplicationContextCallCount == 1)

        let update = try #require(try transport.latestTrainingStateMessage())
        #expect(update.kind == .update)
        #expect(update.requestID == "activation-update")
        #expect(update.isTraining == true)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func refreshPublishesSnapshotWhenSourceProvidesOne() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let snapshot = makeWatchSnapshot()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource(currentSnapshot: { _ in snapshot }),
            now: { Date(timeIntervalSince1970: 1_800_000_013) },
            makeRequestID: { "snapshot-update" }
        )

        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        let update = try #require(try transport.latestTrainingStateMessage())
        #expect(update.kind == .update)
        #expect(update.requestID == "snapshot-update")
        #expect(update.isTraining == true)
        #expect(update.snapshot == snapshot)
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

    @Test func activationFailureIsDiagnosticOnlyAndDoesNotPublish() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        var sourceCallCount = 0
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in
                sourceCallCount += 1
                return true
            }
        )

        sync.bind(modelContext: context)
        sync.activate()
        transport.failActivation("Injected activation failure")

        #expect(sourceCallCount == 0)
        #expect(transport.applicationContexts.isEmpty)
        #expect(transport.updateApplicationContextCallCount == 0)
        #expect(sync.latestDiagnostic == .activationFailed("Injected activation failure"))
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

    @Test func requestReplyReturnsNoTrainingWithoutSnapshot() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in false },
            now: { Date(timeIntervalSince1970: 1_800_000_016) }
        )
        let request = WatchTrainingStateMessage.request(
            requestID: "watch-idle-request",
            sentAt: 1_800_000_000
        )

        sync.bind(modelContext: context)
        sync.activate()

        let reply = try #require(transport.receive(request.propertyList))
        let response = try WatchTrainingStateMessage(propertyList: reply)

        #expect(response.kind == .response)
        #expect(response.requestID == "watch-idle-request")
        #expect(response.isTraining == false)
        #expect(response.snapshot == nil)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func requestReplyIncludesCurrentSnapshot() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let snapshot = makeWatchSnapshot()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource(currentSnapshot: { _ in snapshot }),
            now: { Date(timeIntervalSince1970: 1_800_000_014) }
        )
        let request = WatchTrainingStateMessage.request(
            requestID: "watch-snapshot-request",
            sentAt: 1_800_000_000
        )

        sync.bind(modelContext: context)
        sync.activate()

        let reply = try #require(transport.receive(request.propertyList))
        let response = try WatchTrainingStateMessage(propertyList: reply)

        #expect(response.kind == .response)
        #expect(response.requestID == "watch-snapshot-request")
        #expect(response.isTraining == true)
        #expect(response.snapshot == snapshot)
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

    @Test func refreshWithTransportUnavailableSetsDiagnosticWithoutThrowing() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        transport.updateApplicationContextError = PhoneWatchTrainingStateSync.DiagnosticState.transportUnavailable
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ in true }
        )

        sync.bind(modelContext: context)
        sync.activate()
        sync.refresh()

        #expect(transport.applicationContexts.isEmpty)
        #expect(transport.updateApplicationContextCallCount == 1)
        #expect(sync.latestDiagnostic == .transportUnavailable)

        transport.updateApplicationContextError = nil
        sync.refresh()

        #expect(transport.applicationContexts.count == 1)
        #expect(sync.latestDiagnostic == nil)
    }

    @Test func setSubmissionReplyIsSavedEvenWhenPostSaveRefreshCannotPublish() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Push A",
            exercises: [
                Exercise(name: "Bench Press", defaultRestSeconds: 120, isUnilateral: false, weightUnit: .kilograms),
            ],
            in: context
        )
        let transport = FakePhoneWatchTrainingStateTransport()
        transport.updateApplicationContextError = SentinelWatchSyncError.updateFailed
        let sync = PhoneWatchTrainingStateSync(transport: transport)
        let submission = WatchSetSubmissionMessage(
            clientSubmissionID: "watch-submit-post-save-refresh-failure",
            sentAt: 1_800_000_100,
            sessionID: session.id.uuidString,
            sessionName: "Push A",
            sessionStartedAt: session.startedAt.timeIntervalSince1970,
            exerciseOrderIndex: 0,
            exerciseName: "Bench Press",
            weight: 80,
            weightUnit: "kg",
            reps: 8,
            rpe: nil,
            side: nil,
            completedAt: 1_800_000_101
        )

        sync.bind(modelContext: context)
        sync.activate()

        let reply = try #require(transport.receive(submission.propertyList))
        let ack = try WatchSetSubmissionAck(propertyList: reply)
        let savedSets = try WorkoutSetLogging.setsForExercise(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        )

        #expect(ack.status == .saved)
        #expect(ack.savedSetIndex == 1)
        #expect(ack.completedSetCount == 1)
        #expect(savedSets.count == 1)
        #expect(savedSets[0].weight == 80)
        #expect(savedSets[0].reps == 8)
        #expect(transport.applicationContexts.isEmpty)
        #expect(transport.updateApplicationContextCallCount == 1)
        #expect(sync.latestDiagnostic == .publishFailed("Injected update failure"))
    }

    @Test func requestSourceErrorIsDiagnosticAndDoesNotReply() throws {
        let context = try makeInMemoryContext()
        let transport = FakePhoneWatchTrainingStateTransport()
        let sync = PhoneWatchTrainingStateSync(
            transport: transport,
            source: PhoneTrainingStateSource { _ -> Bool in
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
private func makeSession(
    templateName: String,
    exercises: [Exercise],
    in context: ModelContext
) throws -> WorkoutSession {
    let template = Template(name: templateName)

    context.insert(template)

    for (index, exercise) in exercises.enumerated() {
        context.insert(exercise)
        context.insert(TemplateExercise(template: template, exercise: exercise, orderIndex: index))
    }

    try context.save()

    return try WorkoutSessionLifecycle.createSession(for: template, in: context)
}

private func makeWatchSnapshot() -> WatchWorkoutSnapshot {
    WatchWorkoutSnapshot(
        sessionID: "00000000-0000-0000-0000-000000000011",
        sessionName: "Push A",
        startedAt: 1_800_000_004,
        exercises: [
            WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: 0,
                name: "Bench Press",
                completedSetCount: 3,
                weightUnit: "kg",
                isUnilateral: false,
                defaultRestSeconds: 120
            ),
            WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: 1,
                name: "Lateral Raise",
                completedSetCount: 0,
                weightUnit: "lb",
                isUnilateral: true,
                defaultRestSeconds: 60
            ),
        ]
    )
}

@MainActor
private final class FakePhoneWatchTrainingStateTransport: PhoneWatchTrainingStateTransport {
    private var incomingMessageHandler: (@MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void)?
    private var diagnosticHandler: (@MainActor (String) -> Void)?
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

    func setDiagnosticHandler(_ handler: @escaping @MainActor (String) -> Void) {
        diagnosticHandler = handler
    }

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

    func failActivation(_ message: String) {
        diagnosticHandler?(message)
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
