import Foundation
import SwiftData
import Testing
@testable import DaaiZekBro

@MainActor
struct TrainingScheduleDataTests {
    @Test func cycleSlotsOverridesAndTimezonePersistAfterReload() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let storeURL = directoryURL.appendingPathComponent("Schedule.store")
        let startDate = Date(timeIntervalSince1970: 1_767_225_600)
        let cycleID: UUID

        do {
            let context = try makeContext(storeURL: storeURL)
            let template = Template(name: "Push A", stableID: "template-push")
            let cycle = TrainingCycle(startDate: startDate, timezoneIdentifier: "Asia/Shanghai")
            let firstSlot = TrainingCycleSlot(cycle: cycle, orderIndex: 0, kind: .workout, template: template)
            let restSlot = TrainingCycleSlot(cycle: cycle, orderIndex: 1, kind: .rest)

            context.insert(template)
            context.insert(cycle)
            context.insert(firstSlot)
            context.insert(restSlot)
            try context.save()

            _ = try TrainingDayOverride.upsert(
                cycle: cycle,
                localDateKey: "2026-01-03",
                kind: .workout,
                template: template,
                in: context
            )

            cycleID = cycle.id
        }

        do {
            let context = try makeContext(storeURL: storeURL)
            let cycles = try fetchCycles(in: context)
            let slots = try fetchSlots(in: context).sorted { $0.orderIndex < $1.orderIndex }
            let overrides = try fetchOverrides(in: context)

            #expect(cycles.count == 1)
            #expect(cycles[0].id == cycleID)
            #expect(cycles[0].startDate == startDate)
            #expect(cycles[0].timezoneIdentifier == "Asia/Shanghai")
            #expect(slots.map(\.orderIndex) == [0, 1])
            #expect(slots.map(\.kind) == [.workout, .rest])
            #expect(slots[0].templateStableID == "template-push")
            #expect(overrides.count == 1)
            #expect(overrides[0].localDateKey == "2026-01-03")
            #expect(overrides[0].cycleDateKey == TrainingDayOverride.cycleDateKey(
                cycleID: cycleID,
                localDateKey: "2026-01-03"
            ))
            #expect(overrides[0].templateStableID == "template-push")
        }
    }

    @Test func deletingCycleCascadesSlotsAndOverrides() throws {
        let context = try makeInMemoryContext()
        let template = Template(name: "Push A", stableID: "template-push")
        let cycle = TrainingCycle(timezoneIdentifier: "Asia/Shanghai")
        let workoutSlot = TrainingCycleSlot(cycle: cycle, orderIndex: 0, kind: .workout, template: template)
        let restSlot = TrainingCycleSlot(cycle: cycle, orderIndex: 1, kind: .rest)

        context.insert(template)
        context.insert(cycle)
        context.insert(workoutSlot)
        context.insert(restSlot)
        try context.save()

        _ = try TrainingDayOverride.upsert(
            cycle: cycle,
            localDateKey: "2026-01-03",
            kind: .rest,
            template: nil,
            in: context
        )

        context.delete(cycle)
        try context.save()

        #expect(try fetchCycles(in: context).isEmpty)
        #expect(try fetchSlots(in: context).isEmpty)
        #expect(try fetchOverrides(in: context).isEmpty)
    }

    @Test func deletingTemplatePreservesSlotAndOverrideInvalidPlanSemantics() throws {
        let context = try makeInMemoryContext()
        let template = Template(name: "Push A", stableID: "template-push")
        let cycle = TrainingCycle()
        let workoutSlot = TrainingCycleSlot(cycle: cycle, orderIndex: 0, kind: .workout, template: template)
        let restSlot = TrainingCycleSlot(cycle: cycle, orderIndex: 1, kind: .rest)

        context.insert(template)
        context.insert(cycle)
        context.insert(workoutSlot)
        context.insert(restSlot)
        try context.save()

        _ = try TrainingDayOverride.upsert(
            cycle: cycle,
            localDateKey: "2026-01-03",
            kind: .workout,
            template: template,
            in: context
        )

        try TemplateLibrary.delete(template, in: context)

        let slots = try fetchSlots(in: context).sorted { $0.orderIndex < $1.orderIndex }
        let overrides = try fetchOverrides(in: context)

        #expect(slots.count == 2)
        #expect(slots[0].kind == .workout)
        #expect(slots[0].template == nil)
        #expect(slots[0].templateStableID == "template-push")
        #expect(slots[0].isInvalidPlan)
        #expect(slots[0].isRestDay == false)
        #expect(slots[1].isRestDay)
        #expect(slots[1].isInvalidPlan == false)
        #expect(overrides.count == 1)
        #expect(overrides[0].kind == .workout)
        #expect(overrides[0].template == nil)
        #expect(overrides[0].templateStableID == "template-push")
        #expect(overrides[0].isInvalidPlan)
        #expect(overrides[0].isRestDay == false)
    }

    @Test func upsertingSameCycleAndLocalDateKeepsSingleOverrideWithLatestValue() throws {
        let context = try makeInMemoryContext()
        let push = Template(name: "Push A", stableID: "template-push")
        let pull = Template(name: "Pull A", stableID: "template-pull")
        let cycle = TrainingCycle()

        context.insert(push)
        context.insert(pull)
        context.insert(cycle)
        try context.save()

        let firstOverride = try TrainingDayOverride.upsert(
            cycle: cycle,
            localDateKey: "2026-01-03",
            kind: .workout,
            template: push,
            in: context
        )
        let secondOverride = try TrainingDayOverride.upsert(
            cycle: cycle,
            localDateKey: "2026-01-03",
            kind: .workout,
            template: pull,
            in: context
        )
        let overrides = try fetchOverrides(in: context)

        #expect(firstOverride.persistentModelID == secondOverride.persistentModelID)
        #expect(overrides.count == 1)
        #expect(overrides[0].localDateKey == "2026-01-03")
        #expect(overrides[0].template?.name == "Pull A")
        #expect(overrides[0].templateStableID == "template-pull")
    }

    @Test func seedDataBackfillsTemplateStableIDsAndPreservesThem() throws {
        let context = try makeInMemoryContext()
        let oldPush = Template(name: "Push A", stableID: "")
        let custom = Template(name: "Custom", stableID: "")

        context.insert(oldPush)
        context.insert(custom)
        try context.save()

        try SeedData.writeAndDedup(in: context)

        let templates = try fetchTemplates(in: context)
        let push = try template(named: "Push A", in: context)
        let pushStableID = push.stableID

        #expect(templates.allSatisfy { $0.stableID.isEmpty == false })
        #expect(Set(templates.map(\.stableID)).count == templates.count)

        push.name = "Push Prime"
        try context.save()
        try SeedData.writeAndDedup(in: context)

        #expect(push.stableID == pushStableID)
    }

    @Test func seedDataAssignsDefaultColorsToSeedTemplatesAndLeavesUserTemplatesEmpty() throws {
        let context = try makeInMemoryContext()

        try SeedData.writeAndDedup(in: context)

        #expect(try template(named: "Push A", in: context).colorHex == "#D86838")
        #expect(try template(named: "Push B", in: context).colorHex == "#D86838")
        #expect(try template(named: "Pull A", in: context).colorHex == "#4E7BA6")
        #expect(try template(named: "Pull B", in: context).colorHex == "#4E7BA6")
        #expect(try template(named: "Legs A", in: context).colorHex == "#5C8A3A")
        #expect(try template(named: "Legs B", in: context).colorHex == "#5C8A3A")

        let userTemplate = try TemplateLibrary.create(name: "Push Custom", in: context)
        try SeedData.writeAndDedup(in: context)

        #expect(userTemplate.colorHex == nil)
    }

    @Test func sessionTemplateIdentityBackfillsOnlyFromLiveTemplateRelationAndSurvivesDeletion() throws {
        let context = try makeInMemoryContext()
        let template = Template(name: "Push A", stableID: "template-push")
        let liveRelationSession = WorkoutSession(
            template: template,
            templateNameSnapshot: "Push A",
            templateStableIDSnapshot: "",
            endedAt: Date()
        )
        let brokenRelationSession = WorkoutSession(
            template: nil,
            templateNameSnapshot: "Deleted Template",
            templateStableIDSnapshot: "",
            endedAt: Date()
        )

        context.insert(template)
        context.insert(liveRelationSession)
        context.insert(brokenRelationSession)
        try context.save()

        try SeedData.writeAndDedup(in: context)

        #expect(liveRelationSession.templateStableIDSnapshot == "template-push")
        #expect(brokenRelationSession.templateStableIDSnapshot.isEmpty)

        try TemplateLibrary.delete(template, in: context)

        #expect(liveRelationSession.template == nil)
        #expect(liveRelationSession.templateStableIDSnapshot == "template-push")
        #expect(brokenRelationSession.templateStableIDSnapshot.isEmpty)
    }

    @Test func creatingSessionCopiesTemplateStableIdentity() throws {
        let context = try makeInMemoryContext()
        try SeedData.writeAndDedup(in: context)
        let template = try template(named: "Push A", in: context)

        let session = try WorkoutSessionLifecycle.createSession(for: template, in: context)

        #expect(session.templateStableIDSnapshot == template.stableID)
        #expect(session.templateStableIDSnapshot.isEmpty == false)
    }

    @Test func seedDataDoesNotTreatScheduleOnlyStoreAsEmpty() throws {
        let context = try makeInMemoryContext()

        context.insert(TrainingCycle(timezoneIdentifier: "Asia/Shanghai"))
        try context.save()

        try SeedData.writeAndDedup(in: context)

        #expect(try fetchCycles(in: context).count == 1)
        #expect(try fetchExercises(in: context).isEmpty)
        #expect(try fetchTemplates(in: context).isEmpty)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        try makeContext(storeURL: nil)
    }

    private func makeContext(storeURL: URL?) throws -> ModelContext {
        let schema = Schema([
            Exercise.self,
            Template.self,
            TemplateExercise.self,
            WorkoutSession.self,
            TrainingCycle.self,
            TrainingCycleSlot.self,
            TrainingDayOverride.self,
            WorkoutSessionExerciseSnapshot.self,
            WorkoutSet.self,
        ])
        let configuration: ModelConfiguration

        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])

        return ModelContext(container)
    }

    private func fetchCycles(in context: ModelContext) throws -> [TrainingCycle] {
        try context.fetch(FetchDescriptor<TrainingCycle>())
    }

    private func fetchSlots(in context: ModelContext) throws -> [TrainingCycleSlot] {
        try context.fetch(FetchDescriptor<TrainingCycleSlot>())
    }

    private func fetchOverrides(in context: ModelContext) throws -> [TrainingDayOverride] {
        try context.fetch(FetchDescriptor<TrainingDayOverride>())
    }

    private func fetchTemplates(in context: ModelContext) throws -> [Template] {
        try context.fetch(FetchDescriptor<Template>())
    }

    private func fetchExercises(in context: ModelContext) throws -> [Exercise] {
        try context.fetch(FetchDescriptor<Exercise>())
    }

    private func template(named name: String, in context: ModelContext) throws -> Template {
        guard let template = try fetchTemplates(in: context).first(where: { $0.name == name }) else {
            throw TrainingScheduleDataTestError.missingTemplate(name)
        }

        return template
    }
}

private enum TrainingScheduleDataTestError: Error {
    case missingTemplate(String)
}
