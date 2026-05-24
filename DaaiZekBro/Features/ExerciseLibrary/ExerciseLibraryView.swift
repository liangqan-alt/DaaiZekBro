import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(orderedExercises) { exercise in
                NavigationLink {
                    ExerciseEditorView(exerciseID: exercise.persistentModelID)
                } label: {
                    ExerciseLibraryRow(exercise: exercise)
                }
                .swipeActions(edge: .trailing) {
                    Button("删除", role: .destructive) {
                        delete(exercise)
                    }
                }
            }
        }
        .accessibilityIdentifier("exercise-library-list")
        .overlay {
            if orderedExercises.isEmpty {
                ContentUnavailableView(
                    "暂无动作",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("点击右上角添加动作。")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .dzScreenBackground()
        .navigationTitle("动作库")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ExerciseEditorView(exerciseID: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建动作")
                .accessibilityIdentifier("exercise-library-add-button")
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

    private var orderedExercises: [Exercise] {
        exercises.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func delete(_ exercise: Exercise) {
        do {
            try ExerciseLibrary.delete(exercise, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExerciseLibraryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(DZColor.ink900)

                Text("休息 \(exercise.defaultRestSeconds) 秒\(exercise.isUnilateral ? " · 单侧" : "")")
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

enum ExerciseEditorSavePolicy {
    static func canSave(
        isNewExercise: Bool,
        hasExercise: Bool,
        name: String,
        defaultRestSeconds: Int
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false,
              defaultRestSeconds >= ExerciseLibrary.minimumRestSeconds
        else {
            return false
        }

        return isNewExercise || hasExercise
    }
}

private struct ExerciseEditorView: View {
    let exerciseID: PersistentIdentifier?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]
    @State private var name = ""
    @State private var defaultRestSeconds = 90
    @State private var isUnilateral = false
    @State private var didLoadExercise = false
    @State private var errorMessage: String?

    private var isNewExercise: Bool {
        exerciseID == nil
    }

    private var exercise: Exercise? {
        guard let exerciseID else { return nil }

        return exercises.first { $0.persistentModelID == exerciseID }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        ExerciseEditorSavePolicy.canSave(
            isNewExercise: isNewExercise,
            hasExercise: exercise != nil,
            name: name,
            defaultRestSeconds: defaultRestSeconds
        )
    }

    var body: some View {
        Group {
            if isNewExercise || exercise != nil {
                formContent
            } else {
                ContentUnavailableView(
                    "动作不可用",
                    systemImage: "exclamationmark.triangle",
                    description: Text("该动作可能已被删除。")
                )
                .dzScreenBackground()
            }
        }
        .navigationTitle(isNewExercise ? "新建动作" : "编辑动作")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存", action: save)
                    .disabled(canSave == false)
                    .accessibilityIdentifier("exercise-library-save-button")
            }
        }
        .onAppear(perform: loadExerciseIfNeeded)
        .onChange(of: exercise?.persistentModelID) { _, _ in
            loadExerciseIfNeeded()
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
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                DZSection("动作信息") {
                    TextField("动作名称", text: $name)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(DZColor.ink900)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                    DZDivider()

                    Stepper {
                        defaultRestSeconds += 15
                    } onDecrement: {
                        defaultRestSeconds = max(
                            ExerciseLibrary.minimumRestSeconds,
                            defaultRestSeconds - 15
                        )
                    } label: {
                        HStack {
                            Text("默认休息")
                                .foregroundStyle(DZColor.ink900)

                            Spacer()

                            Text("\(defaultRestSeconds) 秒")
                                .dzNumeric(size: 15)
                                .foregroundStyle(DZColor.ink700)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    DZDivider()

                    Toggle("单侧动作", isOn: $isUnilateral)
                        .tint(DZColor.pump500)
                        .foregroundStyle(DZColor.ink900)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
            .padding(DZMetric.contentPadding)
        }
        .dzScreenBackground()
    }

    private func loadExerciseIfNeeded() {
        guard didLoadExercise == false else { return }
        guard let exercise else { return }

        name = exercise.name
        defaultRestSeconds = exercise.defaultRestSeconds
        isUnilateral = exercise.isUnilateral
        didLoadExercise = true
    }

    private func save() {
        do {
            if isNewExercise {
                _ = try ExerciseLibrary.create(
                    name: trimmedName,
                    defaultRestSeconds: defaultRestSeconds,
                    isUnilateral: isUnilateral,
                    in: modelContext
                )
            } else {
                guard let exercise else { return }

                try ExerciseLibrary.update(
                    exercise,
                    name: trimmedName,
                    defaultRestSeconds: defaultRestSeconds,
                    isUnilateral: isUnilateral,
                    in: modelContext
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView()
    }
    .modelContainer(
        for: [
            Exercise.self,
            Template.self,
            TemplateExercise.self,
            WorkoutSession.self,
            WorkoutSessionExerciseSnapshot.self,
            WorkoutSet.self,
        ],
        inMemory: true
    )
}
