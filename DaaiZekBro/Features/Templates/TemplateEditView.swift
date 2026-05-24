import SwiftData
import SwiftUI

struct TemplateEditView: View {
    let templateID: PersistentIdentifier

    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [Template]
    @State private var name = ""
    @State private var didLoadTemplate = false
    @State private var errorMessage: String?
    @State private var exercisePickerPresentation: TemplateExercisePickerPresentation?

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
        .sheet(item: $exercisePickerPresentation) { presentation in
            TemplateExercisePickerSheet(templateID: presentation.templateID)
        }
        .onAppear(perform: loadTemplateIfNeeded)
        .onChange(of: template?.persistentModelID) { _, _ in
            loadTemplateIfNeeded()
        }
        .alert(
            "操作失败",
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
    }

    private func content(for template: Template) -> some View {
        VStack(spacing: 0) {
            headerContent(for: template)
            exerciseList(for: template)
        }
        .dzScreenBackground()
    }

    private func headerContent(for template: Template) -> some View {
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
                exercisePickerPresentation = TemplateExercisePickerPresentation(templateID: template.persistentModelID)
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

private struct TemplateExercisePickerPresentation: Identifiable {
    let templateID: PersistentIdentifier

    var id: PersistentIdentifier {
        templateID
    }
}

private struct TemplateExercisePickerSheet: View {
    let templateID: PersistentIdentifier

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [Template]
    @Query private var exercises: [Exercise]
    @State private var newExerciseName = ""
    @State private var selectedExerciseIDs: [PersistentIdentifier] = []
    @State private var createdExercises: [Exercise] = []
    @State private var errorMessage: String?

    private var template: Template? {
        templates.first { $0.persistentModelID == templateID }
    }

    private var trimmedNewExerciseName: String {
        newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreateExercise: Bool {
        trimmedNewExerciseName.isEmpty == false
    }

    private var canFinish: Bool {
        selectedExerciseIDs.isEmpty == false
    }

    private var orderedExercises: [Exercise] {
        exercises.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let template {
                    pickerContent(for: template)
                } else {
                    ContentUnavailableView(
                        "模板不可用",
                        systemImage: "exclamationmark.triangle",
                        description: Text("该模板可能已被删除。")
                    )
                    .dzScreenBackground()
                }
            }
            .navigationTitle("添加动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: finish)
                        .disabled(template == nil || canFinish == false)
                        .accessibilityIdentifier("template-exercise-picker-done-button")
                }
            }
            .alert(
                "操作失败",
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
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("template-exercise-picker-sheet")
    }

    private func pickerContent(for template: Template) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                createExerciseSection
                exerciseLibrarySection(for: template)
            }
            .padding(DZMetric.contentPadding)
        }
        .dzScreenBackground()
    }

    private var createExerciseSection: some View {
        DZSection("新建动作") {
            HStack(spacing: DZMetric.rowSpacing) {
                TextField("动作名称", text: $newExerciseName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundStyle(DZColor.ink900)
                    .submitLabel(.done)
                    .onSubmit(createExercise)
                    .accessibilityIdentifier("template-exercise-picker-new-name")

                Button(action: createExercise) {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(DZSecondaryButtonStyle())
                .disabled(canCreateExercise == false)
                .accessibilityIdentifier("template-exercise-picker-create-button")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func exerciseLibrarySection(for template: Template) -> some View {
        DZSection("动作库") {
            if orderedExercises.isEmpty {
                Text("暂无动作")
                    .foregroundStyle(DZColor.ink700)
                    .padding(14)
            } else {
                VStack(spacing: 0) {
                    ForEach(orderedExercises) { exercise in
                        let isAlreadyAdded = templateContains(exercise, in: template)
                        let isSelected = selectedExerciseIDs.contains(exercise.persistentModelID)

                        if isAlreadyAdded {
                            TemplateExercisePickerRow(
                                exercise: exercise,
                                isSelected: false,
                                isAlreadyAdded: true
                            )
                            .accessibilityIdentifier("template-exercise-picker-\(exercise.name)")
                        } else {
                            Button {
                                toggleSelection(for: exercise)
                            } label: {
                                TemplateExercisePickerRow(
                                    exercise: exercise,
                                    isSelected: isSelected,
                                    isAlreadyAdded: false
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("template-exercise-picker-\(exercise.name)")
                        }

                        if exercise.persistentModelID != orderedExercises.last?.persistentModelID {
                            DZDivider()
                        }
                    }
                }
            }
        }
    }

    private func createExercise() {
        guard canCreateExercise else { return }

        do {
            let exercise = try ExerciseLibrary.create(
                name: trimmedNewExerciseName,
                defaultRestSeconds: 90,
                isUnilateral: false,
                in: modelContext
            )

            newExerciseName = ""
            createdExercises.append(exercise)
            select(exercise)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        guard let template else { return }

        let selectedExercises = selectedExerciseIDs.compactMap { selectedID in
            exercises.first { $0.persistentModelID == selectedID }
                ?? createdExercises.first { $0.persistentModelID == selectedID }
        }

        do {
            _ = try TemplateLibrary.appendExercises(selectedExercises, to: template, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleSelection(for exercise: Exercise) {
        if let selectedIndex = selectedExerciseIDs.firstIndex(of: exercise.persistentModelID) {
            selectedExerciseIDs.remove(at: selectedIndex)
        } else {
            select(exercise)
        }
    }

    private func select(_ exercise: Exercise) {
        guard selectedExerciseIDs.contains(exercise.persistentModelID) == false else { return }

        selectedExerciseIDs.append(exercise.persistentModelID)
    }

    private func templateContains(_ exercise: Exercise, in template: Template) -> Bool {
        WorkoutSessionLifecycle.orderedExercises(for: template).contains { existingExercise in
            existingExercise === exercise || existingExercise.persistentModelID == exercise.persistentModelID
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

private struct TemplateExercisePickerRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let isAlreadyAdded: Bool

    var body: some View {
        HStack(spacing: DZMetric.rowSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isAlreadyAdded ? DZColor.fgFaint : DZColor.ink900)

                Text("休息 \(exercise.defaultRestSeconds) 秒\(exercise.isUnilateral ? " · 单侧" : "")")
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
            }

            Spacer(minLength: DZMetric.rowSpacing)

            if isAlreadyAdded {
                Text("已添加")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DZColor.ink700)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DZColor.cream200)
                    .clipShape(Capsule())
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DZColor.pump500)
                    .accessibilityLabel("已选择")
            } else {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(DZColor.fgFaint)
                    .accessibilityLabel("未选择")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
