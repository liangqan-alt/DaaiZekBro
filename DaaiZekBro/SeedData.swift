import Foundation
import SwiftData

enum SeedData {
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

        return templateExerciseNames.map { template in
            Template(
                name: template.name,
                exercises: template.exerciseNames.compactMap { exercisesByName[$0] }
            )
        }
    }

    @MainActor
    static func writeAndDedup(in context: ModelContext) throws {
        let canonicalExercises = try dedupExercises(in: context)
        let exercisesByName = try writeMissingExercises(in: context, existing: canonicalExercises)
        let canonicalTemplates = try dedupTemplates(in: context)

        for templateDefinition in templateExerciseNames {
            let seedExercises = templateDefinition.exerciseNames.compactMap { exercisesByName[$0] }

            if let existingTemplate = canonicalTemplates[templateDefinition.name] {
                existingTemplate.exercises = seedExercises
            } else {
                context.insert(Template(name: templateDefinition.name, exercises: seedExercises))
            }
        }

        try context.save()
    }

    @MainActor
    private static func dedupExercises(in context: ModelContext) throws -> [String: Exercise] {
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        let groupedExercises = Dictionary(grouping: allExercises, by: \.name)
        var canonicalExercises: [String: Exercise] = [:]

        for (name, duplicates) in groupedExercises {
            guard let survivor = duplicates.first else { continue }
            canonicalExercises[name] = survivor

            for duplicate in duplicates.dropFirst() {
                context.delete(duplicate)
            }
        }

        return canonicalExercises
    }

    @MainActor
    private static func writeMissingExercises(
        in context: ModelContext,
        existing: [String: Exercise]
    ) throws -> [String: Exercise] {
        var exercisesByName = existing

        for seedExercise in exercises() {
            if let existingExercise = exercisesByName[seedExercise.name] {
                existingExercise.defaultRestSeconds = seedExercise.defaultRestSeconds
                existingExercise.isUnilateral = seedExercise.isUnilateral
            } else {
                context.insert(seedExercise)
                exercisesByName[seedExercise.name] = seedExercise
            }
        }

        return exercisesByName
    }

    @MainActor
    private static func dedupTemplates(in context: ModelContext) throws -> [String: Template] {
        let allTemplates = try context.fetch(FetchDescriptor<Template>())
        let groupedTemplates = Dictionary(grouping: allTemplates, by: \.name)
        var canonicalTemplates: [String: Template] = [:]

        for (name, duplicates) in groupedTemplates {
            guard let survivor = duplicates.first else { continue }
            canonicalTemplates[name] = survivor

            for duplicate in duplicates.dropFirst() {
                context.delete(duplicate)
            }
        }

        return canonicalTemplates
    }
}
