import Foundation
import SwiftData

enum TemplateLibraryError: Error, LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "模板名称不能为空"
        case .duplicateName(let name):
            "模板名称已存在：\(name)"
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
        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())

        for link in templateExercises where link.template === template {
            context.delete(link)
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
}
