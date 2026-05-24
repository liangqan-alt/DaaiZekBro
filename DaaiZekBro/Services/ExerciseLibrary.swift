import Foundation
import SwiftData

enum ExerciseLibraryError: Error, LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case invalidDefaultRestSeconds(Int)
    case exerciseUsedByOpenSession

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "动作名称不能为空"
        case .duplicateName(let name):
            "动作名称已存在：\(name)"
        case .invalidDefaultRestSeconds(let seconds):
            "默认休息时间不能少于 30 秒，当前为 \(seconds) 秒"
        case .exerciseUsedByOpenSession:
            "进行中的训练正在使用该动作"
        }
    }
}

@MainActor
enum ExerciseLibrary {
    static let minimumRestSeconds = 30

    @discardableResult
    static func create(
        name: String,
        defaultRestSeconds: Int,
        isUnilateral: Bool,
        in context: ModelContext
    ) throws -> Exercise {
        let normalizedName = try validatedName(name, excluding: nil, in: context)
        try validate(defaultRestSeconds: defaultRestSeconds)

        let exercise = Exercise(
            name: normalizedName,
            defaultRestSeconds: defaultRestSeconds,
            isUnilateral: isUnilateral
        )

        context.insert(exercise)
        try context.save()

        return exercise
    }

    static func update(
        _ exercise: Exercise,
        name: String,
        defaultRestSeconds: Int,
        isUnilateral: Bool,
        in context: ModelContext
    ) throws {
        let normalizedName = try validatedName(name, excluding: exercise, in: context)
        try validate(defaultRestSeconds: defaultRestSeconds)

        let isRenaming = exercise.name != normalizedName
        let isChangingUnilateral = exercise.isUnilateral != isUnilateral

        if isRenaming || isChangingUnilateral {
            try ensureExerciseIsNotUsedByOpenSession(exercise, in: context)
        }

        exercise.name = normalizedName
        exercise.defaultRestSeconds = defaultRestSeconds
        exercise.isUnilateral = isUnilateral

        try context.save()
    }

    static func delete(_ exercise: Exercise, in context: ModelContext) throws {
        try ensureExerciseIsNotUsedByOpenSession(exercise, in: context)

        let templates = try context.fetch(FetchDescriptor<Template>())
        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        var affectedTemplates: [Template] = []

        for template in templates {
            template.exercises.removeAll { $0 === exercise }
        }

        for link in templateExercises where link.exercise === exercise {
            if let template = link.template, affectedTemplates.contains(where: { $0 === template }) == false {
                affectedTemplates.append(template)
            }

            context.delete(link)
        }

        for template in affectedTemplates {
            let remainingLinks = templateExercises
                .filter { $0.template === template && $0.exercise !== exercise }
                .sorted(by: templateExerciseSort)

            for (index, link) in remainingLinks.enumerated() {
                link.orderIndex = index
            }
        }

        context.delete(exercise)
        try context.save()
    }

    private static func validatedName(
        _ name: String,
        excluding editedExercise: Exercise?,
        in context: ModelContext
    ) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedName.isEmpty == false else {
            throw ExerciseLibraryError.emptyName
        }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let hasDuplicate = exercises.contains { exercise in
            exercise.name == normalizedName && exercise !== editedExercise
        }

        guard hasDuplicate == false else {
            throw ExerciseLibraryError.duplicateName(normalizedName)
        }

        return normalizedName
    }

    private static func validate(defaultRestSeconds: Int) throws {
        guard defaultRestSeconds >= minimumRestSeconds else {
            throw ExerciseLibraryError.invalidDefaultRestSeconds(defaultRestSeconds)
        }
    }

    private static func ensureExerciseIsNotUsedByOpenSession(
        _ exercise: Exercise,
        in context: ModelContext
    ) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        for session in sessions where session.endedAt == nil {
            let descriptors = try WorkoutSessionLifecycle.exerciseDescriptors(for: session, in: context)

            if descriptors.contains(where: { $0.exercise === exercise }) {
                throw ExerciseLibraryError.exerciseUsedByOpenSession
            }
        }
    }

    private static func templateExerciseSort(_ lhs: TemplateExercise, _ rhs: TemplateExercise) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }

        return (lhs.exercise?.name ?? "") < (rhs.exercise?.name ?? "")
    }
}
