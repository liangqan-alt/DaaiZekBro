import SwiftData
import SwiftUI

struct TemplateListView: View {
    @Binding var path: [AppRoute]
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [Template]
    @Query private var sessions: [WorkoutSession]
    @State private var pendingTemplateName: String?
    @State private var errorMessage: String?
    @State private var isEditingTemplates = false
    @State private var isShowingNameEditor = false
    @State private var editingTemplateID: PersistentIdentifier?
    @State private var pendingDeleteTemplateID: PersistentIdentifier?
    @State private var pendingDeleteTemplateName: String?
    @State private var isShowingDeleteWarning = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        Group {
            if isEditingTemplates {
                editingContent
            } else {
                browsingContent
            }
        }
        .dzScreenBackground()
        .navigationTitle("训练模板")
        .navigationDestination(isPresented: $isShowingNameEditor) {
            TemplateNameEditorView(templateID: editingTemplateID)
        }
        .onChange(of: isShowingNameEditor) { _, isPresented in
            if isPresented == false {
                editingTemplateID = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("daaizeibro-logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditingTemplates {
                    Button {
                        presentCreateTemplate()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建模板")
                    .accessibilityIdentifier("template-add-button")

                    Button("完成") {
                        withAnimation {
                            isEditingTemplates = false
                        }
                    }
                } else {
                    Button("编辑") {
                        withAnimation {
                            isEditingTemplates = true
                        }
                    }

                    NavigationLink(value: AppRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
        }
        .confirmationDialog(
            "已有未结束的训练",
            isPresented: Binding(
                get: { pendingTemplateName != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingTemplateName = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("继续当前训练") {
                continueCurrentWorkout()
            }

            Button("结束当前并新建") {
                resolveConflictByEndingAndCreating()
            }

            Button("丢弃当前并新建", role: .destructive) {
                resolveConflictByDiscardingAndCreating()
            }

            Button("取消", role: .cancel) {
                pendingTemplateName = nil
            }
        } message: {
            Text("请选择如何处理当前训练")
        }
        .confirmationDialog(
            "删除模板？",
            isPresented: $isShowingDeleteWarning,
            titleVisibility: .visible
        ) {
            Button("删除模板", role: .destructive) {
                deletePendingTemplate()
            }

            Button("取消", role: .cancel) {
                clearPendingDelete()
            }
        } message: {
            Text(deleteWarningMessage)
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

    private var browsingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                if let currentOpenSession {
                    continueButton(for: currentOpenSession)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(orderedTemplates) { template in
                        DZTemplateCard(
                            name: template.name,
                            exerciseCount: exerciseCount(for: template)
                        ) {
                            startOrResolveConflict(for: template)
                        }
                        .contextMenu {
                            Button {
                                presentRenameTemplate(template)
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                requestDelete(template)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .accessibilityIdentifier("template-\(template.name)")
                    }
                }
            }
            .padding(DZMetric.contentPadding)
        }
    }

    private var editingContent: some View {
        List {
            ForEach(orderedTemplates) { template in
                Button {
                    path.append(.templateEdit(templateID: template.persistentModelID))
                } label: {
                    TemplateEditRow(
                        name: template.name,
                        exerciseCount: exerciseCount(for: template)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("template-edit-\(template.name)")
            }
            .onMove(perform: moveTemplates)
            .onDelete(perform: deleteTemplates)
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    private var orderedTemplates: [Template] {
        templates.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.name < rhs.name
        }
    }

    private func exerciseCount(for template: Template) -> Int {
        let linkedExerciseCount = template.templateExercises.filter { $0.exercise != nil }.count

        return linkedExerciseCount == 0 ? template.exercises.count : linkedExerciseCount
    }

    private var currentOpenSession: WorkoutSession? {
        sessions
            .filter { $0.endedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var pendingTemplate: Template? {
        guard let pendingTemplateName else { return nil }

        return templates.first { $0.name == pendingTemplateName }
    }

    private var pendingDeleteTemplate: Template? {
        guard let pendingDeleteTemplateID else { return nil }

        return templates.first { $0.persistentModelID == pendingDeleteTemplateID }
    }

    private var deleteWarningMessage: String {
        let templateNameText = pendingDeleteTemplateName.map { "将删除「\($0)」。" } ?? ""

        return "进行中的训练会继续使用开始时的动作快照。\(templateNameText)"
    }

    private func presentCreateTemplate() {
        editingTemplateID = nil
        isShowingNameEditor = true
    }

    private func presentRenameTemplate(_ template: Template) {
        editingTemplateID = template.persistentModelID
        isShowingNameEditor = true
    }

    private func moveTemplates(from source: IndexSet, to destination: Int) {
        var movedTemplates = orderedTemplates
        movedTemplates.move(fromOffsets: source, toOffset: destination)

        do {
            try TemplateLibrary.persistOrder(movedTemplates, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTemplates(at offsets: IndexSet) {
        guard let offset = offsets.first else { return }

        requestDelete(orderedTemplates[offset])
    }

    private func requestDelete(_ template: Template) {
        pendingDeleteTemplateID = template.persistentModelID
        pendingDeleteTemplateName = template.name

        if openSessionUses(template) {
            isShowingDeleteWarning = true
        } else {
            deletePendingTemplate()
        }
    }

    private func deletePendingTemplate() {
        guard let template = pendingDeleteTemplate else {
            clearPendingDelete()
            return
        }

        do {
            try TemplateLibrary.delete(template, in: modelContext)
            clearPendingDelete()
        } catch {
            clearPendingDelete()
            errorMessage = error.localizedDescription
        }
    }

    private func clearPendingDelete() {
        pendingDeleteTemplateID = nil
        pendingDeleteTemplateName = nil
        isShowingDeleteWarning = false
    }

    private func openSessionUses(_ template: Template) -> Bool {
        sessions.contains { session in
            session.endedAt == nil && session.template === template
        }
    }

    private func continueButton(for session: WorkoutSession) -> some View {
        Button {
            path.append(.currentWorkout(sessionID: session.id))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("继续当前训练")
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text(displayName(for: session))

                        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                            Text("已 \(durationText(from: session.startedAt, to: timeline.date))")
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(DZColor.fgOnPump.opacity(0.85))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(DZColor.fgOnPump.opacity(0.85))
            }
            .foregroundStyle(DZColor.fgOnPump)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DZColor.pump500)
            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radius, style: .continuous))
            .dzShadowSM()
        }
        .buttonStyle(.plain)
    }

    private func startOrResolveConflict(for template: Template) {
        do {
            if try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) == nil {
                let session = try WorkoutSessionLifecycle.createSession(for: template, in: modelContext)
                path.append(.currentWorkout(sessionID: session.id))
            } else {
                pendingTemplateName = template.name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func continueCurrentWorkout() {
        do {
            guard let session = try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) else {
                pendingTemplateName = nil
                return
            }

            pendingTemplateName = nil
            path.append(.currentWorkout(sessionID: session.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveConflictByEndingAndCreating() {
        guard let template = pendingTemplate else {
            pendingTemplateName = nil
            return
        }

        do {
            if let session = try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) {
                try WorkoutSessionLifecycle.end(session, in: modelContext)
                UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
            }

            let newSession = try WorkoutSessionLifecycle.createSession(for: template, in: modelContext)
            pendingTemplateName = nil
            path.append(.currentWorkout(sessionID: newSession.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveConflictByDiscardingAndCreating() {
        guard let template = pendingTemplate else {
            pendingTemplateName = nil
            return
        }

        do {
            if let session = try WorkoutSessionLifecycle.currentOpenSession(in: modelContext) {
                try WorkoutSessionLifecycle.discard(session, in: modelContext)
                UserNotificationRestScheduler.cancelPendingRestCompletionNotification()
            }

            let newSession = try WorkoutSessionLifecycle.createSession(for: template, in: modelContext)
            pendingTemplateName = nil
            path.append(.currentWorkout(sessionID: newSession.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func displayName(for session: WorkoutSession) -> String {
        if let templateName = session.template?.name, templateName.isEmpty == false {
            return templateName
        }

        return session.templateNameSnapshot.isEmpty ? "未命名训练" : session.templateNameSnapshot
    }

    private func durationText(from startDate: Date, to endDate: Date) -> String {
        let elapsedSeconds = max(0, Int(endDate.timeIntervalSince(startDate)))
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct TemplateEditRow: View {
    let name: String
    let exerciseCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DZColor.ink900)

                Text("\(exerciseCount) 个动作")
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(DZColor.cream50)
    }
}

enum TemplateNameEditorSavePolicy {
    static func canSave(
        isNewTemplate: Bool,
        hasTemplate: Bool,
        name: String
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedName.isEmpty == false else {
            return false
        }

        return isNewTemplate || hasTemplate
    }
}

private struct TemplateNameEditorView: View {
    let templateID: PersistentIdentifier?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [Template]
    @State private var name = ""
    @State private var didLoadTemplate = false
    @State private var errorMessage: String?

    private var isNewTemplate: Bool {
        templateID == nil
    }

    private var template: Template? {
        guard let templateID else { return nil }

        return templates.first { $0.persistentModelID == templateID }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        TemplateNameEditorSavePolicy.canSave(
            isNewTemplate: isNewTemplate,
            hasTemplate: template != nil,
            name: name
        )
    }

    var body: some View {
        Group {
            if isNewTemplate || template != nil {
                formContent
            } else {
                ContentUnavailableView(
                    "模板不可用",
                    systemImage: "exclamationmark.triangle",
                    description: Text("该模板可能已被删除。")
                )
                .dzScreenBackground()
            }
        }
        .navigationTitle(isNewTemplate ? "新建模板" : "重命名模板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存", action: save)
                    .disabled(canSave == false)
                    .accessibilityIdentifier("template-name-save-button")
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
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                DZSection("模板信息") {
                    TextField("模板名称", text: $name)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(DZColor.ink900)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
            .padding(DZMetric.contentPadding)
        }
        .dzScreenBackground()
    }

    private func loadTemplateIfNeeded() {
        guard didLoadTemplate == false else { return }
        guard let template else { return }

        name = template.name
        didLoadTemplate = true
    }

    private func save() {
        do {
            if isNewTemplate {
                _ = try TemplateLibrary.create(name: trimmedName, in: modelContext)
            } else {
                guard let template else { return }

                try TemplateLibrary.rename(template, name: trimmedName, in: modelContext)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
