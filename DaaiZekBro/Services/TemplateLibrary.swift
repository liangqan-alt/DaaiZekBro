import Foundation
import SwiftData

enum TemplateLibraryError: Error, LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case templateUsedByOpenSession

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "模板名称不能为空"
        case .duplicateName(let name):
            "模板名称已存在：\(name)"
        case .templateUsedByOpenSession:
            "进行中的训练正在使用该模板"
        }
    }
}

@MainActor
enum TemplateLibrary {
    @discardableResult
    static func create(name: String, in context: ModelContext) throws -> Template {
        let normalizedName = try validatedName(name, excluding: nil, in: context)
        let template = Template(
            name: normalizedName,
            sortIndex: try SeedData.nextTemplateSortIndex(in: context)
        )

        context.insert(template)
        try context.save()

        return template
    }

    static func rename(_ template: Template, name: String, in context: ModelContext) throws {
        let normalizedName = try validatedName(name, excluding: template, in: context)

        template.name = normalizedName
        try context.save()
    }

    static func delete(_ template: Template, in context: ModelContext) throws {
        if template.stableID.isEmpty {
            template.stableID = UUID().uuidString
        }

        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let cycleSlots = try context.fetch(FetchDescriptor<TrainingCycleSlot>())
        let dayOverrides = try context.fetch(FetchDescriptor<TrainingDayOverride>())

        for link in templateExercises where link.template === template {
            context.delete(link)
        }

        for session in sessions where session.template === template {
            if session.templateStableIDSnapshot.isEmpty {
                session.templateStableIDSnapshot = template.stableID
            }

            session.template = nil
        }

        for slot in cycleSlots where slot.template === template {
            if slot.templateStableID.isEmpty {
                slot.templateStableID = template.stableID
            }

            slot.template = nil
        }

        for dayOverride in dayOverrides where dayOverride.template === template {
            if dayOverride.templateStableID.isEmpty {
                dayOverride.templateStableID = template.stableID
            }

            dayOverride.template = nil
        }

        context.delete(template)
        try context.save()
    }

    static func persistOrder(_ orderedTemplates: [Template], in context: ModelContext) throws {
        for (index, template) in orderedTemplates.enumerated() {
            template.sortIndex = index
        }

        try context.save()
    }

    static func removeExercise(
        _ exercise: Exercise,
        from template: Template,
        in context: ModelContext
    ) throws {
        try ensureTemplateIsNotUsedByOpenSession(template, in: context)

        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())

        for link in templateExercises where link.template === template && link.exercise === exercise {
            context.delete(link)
        }

        template.exercises.removeAll { $0 === exercise }
        reindexExerciseLinks(
            templateExercises.filter { $0.template === template && $0.exercise !== exercise }
        )

        try context.save()
    }

    static func persistExerciseOrder(
        _ orderedExercises: [Exercise],
        for template: Template,
        in context: ModelContext
    ) throws {
        try ensureTemplateIsNotUsedByOpenSession(template, in: context)

        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        var links = templateExercises.filter { $0.template === template }

        for (index, exercise) in orderedExercises.enumerated()
            where links.contains(where: { $0.exercise === exercise }) == false {
            let link = TemplateExercise(
                template: template,
                exercise: exercise,
                orderIndex: index
            )

            context.insert(link)
            links.append(link)
        }

        for (index, exercise) in orderedExercises.enumerated() {
            links
                .filter { $0.exercise === exercise }
                .forEach { $0.orderIndex = index }
        }

        template.exercises = orderedExercises
        try context.save()
    }

    @discardableResult
    static func appendExercises(
        _ exercises: [Exercise],
        to template: Template,
        in context: ModelContext
    ) throws -> [Exercise] {
        try ensureTemplateIsNotUsedByOpenSession(template, in: context)

        var orderedExercises = WorkoutSessionLifecycle.orderedExercises(for: template)
        var appendedExercises: [Exercise] = []

        for exercise in exercises where orderedExercises.containsSameExercise(as: exercise) == false {
            orderedExercises.append(exercise)
            appendedExercises.append(exercise)
        }

        guard appendedExercises.isEmpty == false else {
            return []
        }

        try persistExerciseOrder(orderedExercises, for: template, in: context)

        return appendedExercises
    }

    private static func validatedName(
        _ name: String,
        excluding editedTemplate: Template?,
        in context: ModelContext
    ) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedName.isEmpty == false else {
            throw TemplateLibraryError.emptyName
        }

        let templates = try context.fetch(FetchDescriptor<Template>())
        let hasDuplicate = templates.contains { template in
            template.name == normalizedName && template !== editedTemplate
        }

        guard hasDuplicate == false else {
            throw TemplateLibraryError.duplicateName(normalizedName)
        }

        return normalizedName
    }

    private static func ensureTemplateIsNotUsedByOpenSession(
        _ template: Template,
        in context: ModelContext
    ) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())

        if sessions.contains(where: { $0.endedAt == nil && $0.template === template }) {
            throw TemplateLibraryError.templateUsedByOpenSession
        }
    }

    private static func reindexExerciseLinks(_ links: [TemplateExercise]) {
        for (index, link) in links.sortedByTemplateExerciseOrder().enumerated() {
            link.orderIndex = index
        }
    }
}

private extension Array where Element == Exercise {
    func containsSameExercise(as exercise: Exercise) -> Bool {
        contains { existingExercise in
            existingExercise === exercise || existingExercise.persistentModelID == exercise.persistentModelID
        }
    }
}
