import SwiftData
import SwiftUI

struct TemplateEditView: View {
    let templateID: PersistentIdentifier

    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [Template]
    @State private var name = ""
    @State private var didLoadTemplate = false
    @State private var errorMessage: String?
    @State private var isShowingAddPlaceholder = false

    private var template: Template? {
        templates.first { $0.persistentModelID == templateID }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveName: Bool {
        guard let template else { return false }

        return TemplateNameEditorSavePolicy.canSave(
            isNewTemplate: false,
            hasTemplate: true,
            name: name
        ) && trimmedName != template.name
    }

    var body: some View {
        Group {
            if let template {
                content(for: template)
            } else {
                ContentUnavailableView(
                    "模板不可用",
                    systemImage: "exclamationmark.triangle",
                    description: Text("该模板可能已被删除。")
                )
                .dzScreenBackground()
            }
        }
        .navigationTitle("编辑模板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存", action: saveName)
                    .disabled(canSaveName == false)
                    .accessibilityIdentifier("template-edit-save-button")
            }
        }
        .onAppear(perform: loadTemplateIfNeeded)
        .onChange(of: template?.persistentModelID) { _, _ in
            loadTemplateIfNeeded()
        }
        .alert(
            "保存失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("添加动作", isPresented: $isShowingAddPlaceholder) {
            Button("好", role: .cancel) {}
        } message: {
            Text("添加动作将在后续切片支持。")
        }
    }

    private func content(for template: Template) -> some View {
        VStack(spacing: 0) {
            headerContent
            exerciseList(for: template)
        }
        .dzScreenBackground()
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
            DZSection("模板信息") {
                TextField("模板名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundStyle(DZColor.ink900)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }

            Button {
                isShowingAddPlaceholder = true
            } label: {
                Label("添加动作", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DZPrimaryButtonStyle())
            .accessibilityIdentifier("template-edit-add-exercise-button")
        }
        .padding(DZMetric.contentPadding)
    }

    private func exerciseList(for template: Template) -> some View {
        let exercises = orderedExercises(for: template)

        return List {
            if exercises.isEmpty {
                Text("暂无动作")
                    .foregroundStyle(DZColor.ink700)
                    .listRowBackground(DZColor.cream50)
            } else {
                ForEach(exercises) { exercise in
                    TemplateExerciseEditRow(exercise: exercise)
                        .accessibilityIdentifier("template-exercise-\(exercise.name)")
                }
                .onMove { source, destination in
                    moveExercises(for: template, from: source, to: destination)
                }
                .onDelete { offsets in
                    removeExercises(from: template, at: offsets)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
        .accessibilityIdentifier("template-edit-exercise-list")
    }

    private func orderedExercises(for template: Template) -> [Exercise] {
        WorkoutSessionLifecycle.orderedExercises(for: template)
    }

    private func loadTemplateIfNeeded() {
        guard didLoadTemplate == false else { return }
        guard let template else { return }

        name = template.name
        didLoadTemplate = true
    }

    private func saveName() {
        guard let template else { return }

        do {
            try TemplateLibrary.rename(template, name: trimmedName, in: modelContext)
            name = template.name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveExercises(
        for template: Template,
        from source: IndexSet,
        to destination: Int
    ) {
        var exercises = orderedExercises(for: template)
        exercises.move(fromOffsets: source, toOffset: destination)

        do {
            try TemplateLibrary.persistExerciseOrder(exercises, for: template, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeExercises(from template: Template, at offsets: IndexSet) {
        let exercises = orderedExercises(for: template)

        do {
            for offset in offsets.sorted(by: >) where exercises.indices.contains(offset) {
                try TemplateLibrary.removeExercise(exercises[offset], from: template, in: modelContext)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TemplateExerciseEditRow: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DZColor.ink900)

                Text("休息 \(exercise.defaultRestSeconds) 秒\(exercise.isUnilateral ? " · 单侧" : "")")
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(DZColor.cream50)
    }
}

#Preview {
    NavigationStack {
        ContentUnavailableView(
            "模板不可用",
            systemImage: "exclamationmark.triangle",
            description: Text("该模板可能已被删除。")
        )
    }
}
