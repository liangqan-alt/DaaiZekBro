import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct WatchSetSubmissionMessageTests {
    @Test func setSubmissionMessageRoundTripsThroughPropertyList() throws {
        let message = WatchSetSubmissionMessage(
            clientSubmissionID: "watch-submit-1",
            sentAt: 1_800_000_100,
            sessionID: "00000000-0000-0000-0000-000000000111",
            exerciseOrderIndex: 1,
            exerciseName: "Lateral Raise",
            weight: 100,
            weightUnit: "lb",
            reps: 12,
            rpe: 8,
            side: "right",
            completedAt: 1_800_000_101
        )

        let decoded = try WatchSetSubmissionMessage(propertyList: message.propertyList)

        #expect(decoded == message)
        #expect(decoded.propertyList["kind"] as? String == "setSubmission.submit")
        #expect(decoded.propertyList["clientSubmissionID"] as? String == "watch-submit-1")
    }

    @Test func setSubmissionAckRoundTripsThroughPropertyList() throws {
        let saved = WatchSetSubmissionAck.saved(
            clientSubmissionID: "watch-submit-1",
            savedSetIndex: 2,
            completedSetCount: 4
        )
        let rejected = WatchSetSubmissionAck.rejected(
            clientSubmissionID: "watch-submit-2",
            errorCode: .invalidWeight,
            message: "bad weight"
        )

        #expect(try WatchSetSubmissionAck(propertyList: saved.propertyList) == saved)
        #expect(try WatchSetSubmissionAck(propertyList: rejected.propertyList) == rejected)
        #expect(saved.propertyList["status"] as? String == "saved")
        #expect(rejected.propertyList["errorCode"] as? String == "invalidWeight")
    }

    @Test func invalidSubmissionFieldsFailDecoding() {
        expectParseError(.invalidSchemaVersion) {
            _ = try WatchSetSubmissionMessage(propertyList: [
                "schemaVersion": 2,
                "kind": "setSubmission.submit",
            ])
        }

        expectParseError(.invalidClientSubmissionID) {
            _ = try WatchSetSubmissionMessage(propertyList: baseSubmissionPropertyList(clientSubmissionID: ""))
        }

        expectParseError(.invalidWeightUnit) {
            _ = try WatchSetSubmissionMessage(propertyList: baseSubmissionPropertyList(weightUnit: "stone"))
        }

        expectParseError(.invalidSide) {
            _ = try WatchSetSubmissionMessage(propertyList: baseSubmissionPropertyList(side: "center"))
        }
    }

    private func expectParseError(
        _ expectedError: WatchSetSubmissionMessage.ParseError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected \(expectedError)")
        } catch let error as WatchSetSubmissionMessage.ParseError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

@MainActor
struct PhoneWatchSetSubmissionHandlerTests {
    @Test func onlineSubmissionSavesOneSetAndReturnsSavedAck() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Push A",
            exercises: [
                Exercise(name: "Bench Press", defaultRestSeconds: 120, isUnilateral: false, weightUnit: .kilograms),
            ],
            in: context
        )
        let submission = makeSubmission(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Bench Press",
            weight: 80,
            weightUnit: "kg",
            reps: 8
        )

        let ack = PhoneWatchSetSubmissionHandler.handle(submission, in: context)

        #expect(ack.status == .saved)
        #expect(ack.savedSetIndex == 1)
        #expect(ack.completedSetCount == 1)

        let savedSets = try WorkoutSetLogging.setsForExercise(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            in: context
        )
        #expect(savedSets.count == 1)
        #expect(savedSets[0].weight == 80)
        #expect(savedSets[0].reps == 8)
        #expect(savedSets[0].rpe == nil)
        #expect(savedSets[0].side == nil)
    }

    @Test func submissionUsesOrderIndexForDuplicateExerciseNamesAndConvertsPounds() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Pull A",
            exercises: [
                Exercise(name: "Cable Row", defaultRestSeconds: 90, isUnilateral: false, weightUnit: .kilograms),
                Exercise(name: "Cable Row", defaultRestSeconds: 90, isUnilateral: false, weightUnit: .pounds),
            ],
            in: context
        )
        let submission = makeSubmission(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            exerciseName: "Cable Row",
            weight: 100,
            weightUnit: "lb",
            reps: 10
        )

        let ack = PhoneWatchSetSubmissionHandler.handle(submission, in: context)

        #expect(ack.status == .saved)
        #expect(try WorkoutSetLogging.setsForExercise(sessionID: session.id, exerciseOrderIndex: 0, in: context).isEmpty)

        let savedSets = try WorkoutSetLogging.setsForExercise(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            in: context
        )
        #expect(savedSets.count == 1)
        #expect(abs(savedSets[0].weight - 45.3592) < 0.000001)
    }

    @Test func submissionRejectsSideValidationFailuresWithoutSaving() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Accessory",
            exercises: [
                Exercise(name: "Lateral Raise", defaultRestSeconds: 60, isUnilateral: true, weightUnit: .kilograms),
                Exercise(name: "Bench Press", defaultRestSeconds: 120, isUnilateral: false, weightUnit: .kilograms),
            ],
            in: context
        )
        let missingSide = makeSubmission(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            exerciseName: "Lateral Raise",
            side: nil
        )
        let extraSide = makeSubmission(
            sessionID: session.id,
            exerciseOrderIndex: 1,
            exerciseName: "Bench Press",
            side: "left"
        )

        let missingSideAck = PhoneWatchSetSubmissionHandler.handle(missingSide, in: context)
        let extraSideAck = PhoneWatchSetSubmissionHandler.handle(extraSide, in: context)

        #expect(missingSideAck.status == .rejected)
        #expect(missingSideAck.errorCode == .missingSide)
        #expect(extraSideAck.status == .rejected)
        #expect(extraSideAck.errorCode == .sideNotAllowed)
        #expect(try context.fetch(FetchDescriptor<WorkoutSet>()).isEmpty)
    }
}

@MainActor
struct WatchWorkoutSnapshotReferenceTests {
    @Test func snapshotIncludesSideCountsAndCurrentSessionReferenceFirst() throws {
        let context = try makeInMemoryContext()
        let session = try makeSession(
            templateName: "Push A",
            exercises: [
                Exercise(name: "Lateral Raise", defaultRestSeconds: 60, isUnilateral: true, weightUnit: .kilograms),
            ],
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            weight: 10,
            reps: 12,
            rpe: nil,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: session.id,
            exerciseOrderIndex: 0,
            weight: 12.5,
            reps: 10,
            rpe: nil,
            side: .right,
            completedAt: Date(timeIntervalSince1970: 110),
            in: context
        )

        let snapshot = try #require(try PhoneTrainingStateSource.live.currentSnapshot(context))
        let exercise = try #require(snapshot.exercises.first)

        #expect(exercise.completedSetCount == 2)
        #expect(exercise.leftCompletedSetCount == 1)
        #expect(exercise.rightCompletedSetCount == 1)
        #expect(exercise.lastSetReference == WatchWorkoutSnapshot.LastSetReference(
            weight: 12.5,
            reps: 10,
            source: "currentSession"
        ))
    }

    @Test func snapshotFallsBackToHistoricalReferenceAndAllowsNoReference() throws {
        let context = try makeInMemoryContext()
        let historicalSession = try makeSession(
            templateName: "Old Push",
            exercises: [
                Exercise(name: "Bench Press", defaultRestSeconds: 120, isUnilateral: false, weightUnit: .pounds),
            ],
            in: context
        )
        _ = try WorkoutSetLogging.recordSet(
            sessionID: historicalSession.id,
            exerciseOrderIndex: 0,
            weight: 45.3592,
            reps: 9,
            rpe: nil,
            side: nil,
            completedAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        try WorkoutSessionLifecycle.end(historicalSession, in: context)

        _ = try makeSession(
            templateName: "New Push",
            exercises: [
                Exercise(name: "Bench Press", defaultRestSeconds: 120, isUnilateral: false, weightUnit: .pounds),
                Exercise(name: "Dip", defaultRestSeconds: 90, isUnilateral: false, weightUnit: .kilograms),
            ],
            in: context
        )

        let snapshot = try #require(try PhoneTrainingStateSource.live.currentSnapshot(context))
        let bench = try #require(snapshot.exercises.first { $0.name == "Bench Press" })
        let dip = try #require(snapshot.exercises.first { $0.name == "Dip" })

        #expect(abs((bench.lastSetReference?.weight ?? 0) - 100) < 0.000001)
        #expect(bench.lastSetReference?.reps == 9)
        #expect(bench.lastSetReference?.source == "history")
        #expect(dip.lastSetReference == nil)
    }

    @Test func oldCachedSnapshotPayloadDecodesWithReferenceDefaults() throws {
        let decoded = try WatchWorkoutSnapshot(propertyList: [
            "sessionID": "00000000-0000-0000-0000-000000000222",
            "sessionName": "Push A",
            "startedAt": TimeInterval(1_800_000_000),
            "exercises": [[
                "exerciseOrderIndex": 0,
                "name": "Bench Press",
                "completedSetCount": 2,
                "weightUnit": "kg",
                "isUnilateral": false,
                "defaultRestSeconds": 120,
            ]],
        ])

        let exercise = try #require(decoded.exercises.first)
        #expect(exercise.leftCompletedSetCount == 0)
        #expect(exercise.rightCompletedSetCount == 0)
        #expect(exercise.lastSetReference == nil)
    }
}

struct WatchRecordDraftTests {
    @Test func draftDoesNotPrefillFromReferenceAndInfersSide() {
        let reference = WatchWorkoutSnapshot.LastSetReference(
            weight: 42.5,
            reps: 8,
            source: "history"
        )
        let draft = WatchRecordDraft(
            isUnilateral: true,
            leftCompletedSetCount: 2,
            rightCompletedSetCount: 1,
            reference: reference
        )

        #expect(draft.weight == 0)
        #expect(draft.reps == 10)
        #expect(draft.side == "right")
        #expect(draft.reference == reference)
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

private func makeSubmission(
    sessionID: UUID,
    exerciseOrderIndex: Int,
    exerciseName: String,
    weight: Double = 10,
    weightUnit: String = "kg",
    reps: Int = 8,
    rpe: Int? = nil,
    side: String? = nil
) -> WatchSetSubmissionMessage {
    WatchSetSubmissionMessage(
        clientSubmissionID: UUID().uuidString,
        sentAt: 1_800_000_100,
        sessionID: sessionID.uuidString,
        exerciseOrderIndex: exerciseOrderIndex,
        exerciseName: exerciseName,
        weight: weight,
        weightUnit: weightUnit,
        reps: reps,
        rpe: rpe,
        side: side,
        completedAt: 1_800_000_101
    )
}

private func baseSubmissionPropertyList(
    clientSubmissionID: String = "watch-submit-1",
    weightUnit: String = "kg",
    side: String? = nil
) -> [String: Any] {
    var propertyList: [String: Any] = [
        "schemaVersion": WatchSetSubmissionMessage.schemaVersion,
        "kind": "setSubmission.submit",
        "clientSubmissionID": clientSubmissionID,
        "sentAt": TimeInterval(1_800_000_100),
        "sessionID": "00000000-0000-0000-0000-000000000111",
        "exerciseOrderIndex": 0,
        "exerciseName": "Bench Press",
        "weight": 80.0,
        "weightUnit": weightUnit,
        "reps": 8,
        "completedAt": TimeInterval(1_800_000_101),
    ]

    if let side {
        propertyList["side"] = side
    }

    return propertyList
}
