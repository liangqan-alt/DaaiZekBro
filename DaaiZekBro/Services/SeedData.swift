import Foundation
import SwiftData

enum SeedData {
    static let pushTemplateColorHex = "#D86838"
    static let pullTemplateColorHex = "#4E7BA6"
    static let legsTemplateColorHex = "#5C8A3A"

    static let templateExerciseNames: [(name: String, exerciseNames: [String])] = [
        ("Push A", [
            "固定器械卧推",
            "上斜推胸机",
            "固定器械推肩",
            "坐姿夹胸",
            "哑铃侧平举",
            "坐姿肱三头伸展机",
        ]),
        ("Push B", [
            "上斜推胸机",
            "固定器械卧推",
            "固定器械推肩",
            "坐姿夹胸",
            "哑铃侧平举",
            "坐姿肱三头伸展机",
        ]),
        ("Pull A", [
            "龙门架宽距高位下拉",
            "固定器械胸托划船",
            "绳索面拉",
            "坐姿二头弯举机",
            "绳索卷腹",
        ]),
        ("Pull B", [
            "固定器械高位下拉",
            "固定器械胸托划船",
            "绳索面拉",
            "坐姿二头弯举机",
            "反向卷腹",
        ]),
        ("Legs A", [
            "腿举机",
            "腿屈伸机",
            "跪姿单腿腿弯举",
            "臀推机",
            "髋外展",
        ]),
        ("Legs B", [
            "臀推机",
            "腿举机",
            "跪姿单腿腿弯举",
            "罗马椅背伸",
            "腿屈伸机",
            "绳索卷腹",
        ]),
    ]

    static func exercises() -> [Exercise] {
        [
            Exercise(name: "固定器械卧推", defaultRestSeconds: 120, isUnilateral: false),
            Exercise(name: "上斜推胸机", defaultRestSeconds: 120, isUnilateral: false),
            Exercise(name: "固定器械推肩", defaultRestSeconds: 120, isUnilateral: false),
            Exercise(name: "坐姿夹胸", defaultRestSeconds: 90, isUnilateral: false),
            Exercise(name: "哑铃侧平举", defaultRestSeconds: 75, isUnilateral: false),
            Exercise(name: "坐姿肱三头伸展机", defaultRestSeconds: 75, isUnilateral: false),
            Exercise(name: "龙门架宽距高位下拉", defaultRestSeconds: 150, isUnilateral: false),
            Exercise(name: "固定器械高位下拉", defaultRestSeconds: 150, isUnilateral: false),
            Exercise(name: "固定器械胸托划船", defaultRestSeconds: 150, isUnilateral: false),
            Exercise(name: "绳索面拉", defaultRestSeconds: 75, isUnilateral: false),
            Exercise(name: "坐姿二头弯举机", defaultRestSeconds: 75, isUnilateral: false),
            Exercise(name: "绳索卷腹", defaultRestSeconds: 60, isUnilateral: false),
            Exercise(name: "反向卷腹", defaultRestSeconds: 60, isUnilateral: false),
            Exercise(name: "腿举机", defaultRestSeconds: 150, isUnilateral: false),
            Exercise(name: "腿屈伸机", defaultRestSeconds: 75, isUnilateral: false),
            Exercise(name: "跪姿单腿腿弯举", defaultRestSeconds: 75, isUnilateral: true),
            Exercise(name: "臀推机", defaultRestSeconds: 150, isUnilateral: false),
            Exercise(name: "髋外展", defaultRestSeconds: 75, isUnilateral: false),
            Exercise(name: "罗马椅背伸", defaultRestSeconds: 75, isUnilateral: false),
        ]
    }

    static func templates(allExercises: [Exercise]) -> [Template] {
        let exercisesByName = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.name, $0) })

        return templateExerciseNames.enumerated().map { index, template in
            Template(
                name: template.name,
                exercises: template.exerciseNames.compactMap { exercisesByName[$0] },
                sortIndex: index,
                colorHex: defaultColorHex(forSeedTemplateName: template.name)
            )
        }
    }

    @MainActor
    static func writeAndDedup(in context: ModelContext) throws {
        if try isStoreEmpty(in: context) {
            try writeInitialSeed(in: context)
            try context.save()
            return
        }

        try dedupExercises(in: context)
        try dedupTemplates(in: context)
        try backfillTemplateSortIndexes(in: context)
        try backfillTemplateExercises(in: context)
        try backfillTemplateStableIDs(in: context)
        try backfillSeedTemplateColors(in: context)
        try backfillSessionTemplateStableIDs(in: context)
        try context.save()
    }

    @MainActor
    static func nextTemplateSortIndex(in context: ModelContext) throws -> Int {
        let templates = try context.fetch(FetchDescriptor<Template>())

        return (templates.map(\.sortIndex).max() ?? -1) + 1
    }

    @MainActor
    private static func isStoreEmpty(in context: ModelContext) throws -> Bool {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let templates = try context.fetch(FetchDescriptor<Template>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        let cycles = try context.fetch(FetchDescriptor<TrainingCycle>())
        let slots = try context.fetch(FetchDescriptor<TrainingCycleSlot>())
        let dayOverrides = try context.fetch(FetchDescriptor<TrainingDayOverride>())

        return exercises.isEmpty
            && templates.isEmpty
            && sessions.isEmpty
            && sets.isEmpty
            && cycles.isEmpty
            && slots.isEmpty
            && dayOverrides.isEmpty
    }

    @MainActor
    private static func writeInitialSeed(in context: ModelContext) throws {
        let seedExercises = exercises()
        let exercisesByName = Dictionary(uniqueKeysWithValues: seedExercises.map { ($0.name, $0) })

        for exercise in seedExercises {
            context.insert(exercise)
        }

        for (templateIndex, templateDefinition) in templateExerciseNames.enumerated() {
            let seedExercises = templateDefinition.exerciseNames.compactMap { exercisesByName[$0] }
            let template = Template(
                name: templateDefinition.name,
                exercises: seedExercises,
                sortIndex: templateIndex,
                colorHex: defaultColorHex(forSeedTemplateName: templateDefinition.name)
            )

            context.insert(template)

            for (exerciseIndex, exercise) in seedExercises.enumerated() {
                context.insert(TemplateExercise(template: template, exercise: exercise, orderIndex: exerciseIndex))
            }
        }
    }

    @MainActor
    private static func dedupExercises(in context: ModelContext) throws {
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        let groupedExercises = Dictionary(grouping: allExercises, by: \.name)
        let templates = try context.fetch(FetchDescriptor<Template>())
        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        let sessionSnapshots = try context.fetch(FetchDescriptor<WorkoutSessionExerciseSnapshot>())
        let workoutSets = try context.fetch(FetchDescriptor<WorkoutSet>())

        for (_, duplicates) in groupedExercises {
            guard let survivor = duplicates.first else { continue }

            for duplicate in duplicates.dropFirst() {
                for template in templates where template.exercises.contains(where: { $0 === duplicate }) {
                    template.exercises = template.exercises.map { exercise in
                        exercise === duplicate ? survivor : exercise
                    }
                }

                for templateExercise in templateExercises where templateExercise.exercise === duplicate {
                    templateExercise.exercise = survivor
                }

                for snapshot in sessionSnapshots where snapshot.exercise === duplicate {
                    snapshot.exercise = survivor
                }

                for set in workoutSets where set.exercise === duplicate {
                    set.exercise = survivor
                }

                context.delete(duplicate)
            }
        }
    }

    @MainActor
    private static func dedupTemplates(in context: ModelContext) throws {
        let allTemplates = try context.fetch(FetchDescriptor<Template>())
        let groupedTemplates = Dictionary(grouping: allTemplates, by: \.name)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        let cycleSlots = try context.fetch(FetchDescriptor<TrainingCycleSlot>())
        let dayOverrides = try context.fetch(FetchDescriptor<TrainingDayOverride>())

        for (_, duplicates) in groupedTemplates {
            guard let survivor = duplicates.first else { continue }
            var survivorHasTemplateExercises = templateExercises.contains { $0.template === survivor }

            for duplicate in duplicates.dropFirst() {
                if survivor.stableID.isEmpty, duplicate.stableID.isEmpty == false {
                    survivor.stableID = duplicate.stableID
                }

                if survivor.colorHex == nil {
                    survivor.colorHex = duplicate.colorHex
                }

                if survivor.exercises.isEmpty {
                    survivor.exercises = duplicate.exercises
                }

                for session in sessions where session.template === duplicate {
                    session.template = survivor
                }

                for slot in cycleSlots where slot.template === duplicate {
                    slot.template = survivor
                    if survivor.stableID.isEmpty == false {
                        slot.templateStableID = survivor.stableID
                    }
                }

                for dayOverride in dayOverrides where dayOverride.template === duplicate {
                    dayOverride.template = survivor
                    if survivor.stableID.isEmpty == false {
                        dayOverride.templateStableID = survivor.stableID
                    }
                }

                for templateExercise in templateExercises where templateExercise.template === duplicate {
                    if survivorHasTemplateExercises {
                        context.delete(templateExercise)
                    } else {
                        templateExercise.template = survivor
                    }
                }

                survivorHasTemplateExercises = true
                context.delete(duplicate)
            }
        }
    }

    @MainActor
    private static func backfillTemplateStableIDs(in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<Template>())
        var usedStableIDs = Set(templates.map(\.stableID).filter { $0.isEmpty == false })

        for template in templates where template.stableID.isEmpty {
            var stableID = UUID().uuidString

            while usedStableIDs.contains(stableID) {
                stableID = UUID().uuidString
            }

            template.stableID = stableID
            usedStableIDs.insert(stableID)
        }
    }

    @MainActor
    private static func backfillSeedTemplateColors(in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<Template>())

        for template in templates where template.colorHex == nil {
            guard let colorHex = defaultColorHex(forSeedTemplateName: template.name) else {
                continue
            }

            template.colorHex = colorHex
        }
    }

    @MainActor
    private static func backfillSessionTemplateStableIDs(in context: ModelContext) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        for session in sessions where session.templateStableIDSnapshot.isEmpty {
            guard let templateStableID = session.template?.stableID, templateStableID.isEmpty == false else {
                continue
            }

            session.templateStableIDSnapshot = templateStableID
        }
    }

    @MainActor
    private static func backfillTemplateSortIndexes(in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<Template>())
        guard templates.isEmpty == false else { return }

        let sortedIndexes = templates.map(\.sortIndex).sorted()
        let expectedIndexes = Array(0..<templates.count)

        guard sortedIndexes != expectedIndexes else {
            return
        }

        let allIndexesAreDefault = Set(templates.map(\.sortIndex)) == Set([0])
        let seedIndexes = Dictionary(uniqueKeysWithValues: templateExerciseNames.enumerated().map { index, template in
            (template.name, index)
        })

        let orderedTemplates = templates.sorted { lhs, rhs in
            if allIndexesAreDefault {
                let lhsSeedIndex = seedIndexes[lhs.name]
                let rhsSeedIndex = seedIndexes[rhs.name]

                switch (lhsSeedIndex, rhsSeedIndex) {
                case let (lhsSeedIndex?, rhsSeedIndex?):
                    return lhsSeedIndex < rhsSeedIndex
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name < rhs.name
                }
            }

            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.name < rhs.name
        }

        for (index, template) in orderedTemplates.enumerated() {
            template.sortIndex = index
        }
    }

    @MainActor
    private static func backfillTemplateExercises(in context: ModelContext) throws {
        let templates = try context.fetch(FetchDescriptor<Template>())
        let allTemplateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())

        for template in templates {
            let links = allTemplateExercises.filter { $0.template === template }

            if links.isEmpty {
                let orderedExercises = orderedExercisesForBackfill(template)

                for (index, exercise) in orderedExercises.enumerated() {
                    context.insert(TemplateExercise(template: template, exercise: exercise, orderIndex: index))
                }

                continue
            }

            for (index, link) in links.sortedByTemplateExerciseOrder().enumerated() {
                link.orderIndex = index
            }
        }
    }

    private static func orderedExercisesForBackfill(_ template: Template) -> [Exercise] {
        guard let seedTemplate = templateExerciseNames.first(where: { $0.name == template.name }) else {
            return template.exercises
        }

        var remainingExercises = template.exercises
        var orderedExercises: [Exercise] = []

        for exerciseName in seedTemplate.exerciseNames {
            guard let exerciseIndex = remainingExercises.firstIndex(where: { $0.name == exerciseName }) else {
                continue
            }

            orderedExercises.append(remainingExercises.remove(at: exerciseIndex))
        }

        orderedExercises.append(contentsOf: remainingExercises)

        return orderedExercises
    }

    private static func defaultColorHex(forSeedTemplateName name: String) -> String? {
        guard templateExerciseNames.contains(where: { $0.name == name }) else {
            return nil
        }

        if name.hasPrefix("Push") {
            return pushTemplateColorHex
        }

        if name.hasPrefix("Pull") {
            return pullTemplateColorHex
        }

        if name.hasPrefix("Legs") {
            return legsTemplateColorHex
        }

        return nil
    }
}
