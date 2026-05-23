import SwiftData
import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var sets: [WorkoutSet]
    @State private var selection = Set<UUID>()
    @State private var preparedShareURL: URL?
    @State private var errorMessage: String?
    @State private var isShowingDeleteConfirmation = false

    private var sections: [WorkoutHistoryMonthSection] {
        WorkoutHistoryData.sections(
            sessions: sessions,
            sets: sets,
            now: Date(),
            calendar: .current
        )
    }

    private var visibleSessionIDs: Set<UUID> {
        Set(sections.flatMap { section in section.rows.map(\.id) })
    }

    private var selectedRows: [WorkoutHistoryRow] {
        sections
            .flatMap(\.rows)
            .filter { selection.contains($0.id) }
    }

    private var selectedContainsOpenSession: Bool {
        selectedRows.contains { $0.summary.endedAt == nil }
    }

    private var isSelecting: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        if isSelecting {
                            WorkoutHistoryRowView(row: row)
                                .tag(row.id)
                        } else {
                            NavigationLink {
                                WorkoutHistoryDetailView(sessionID: row.id)
                            } label: {
                                WorkoutHistoryRowView(row: row)
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.45)
                                    .onEnded { _ in
                                        beginSelection(with: row.id)
                                    }
                            )
                            .tag(row.id)
                        }
                    }
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView(
                    "暂无训练记录",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("完成训练后会显示在这里。")
                )
            }
        }
        .dzScreenBackground()
        .navigationTitle("训练历史")
        .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
        .toolbar {
            topToolbar
            bottomToolbar
        }
        .confirmationDialog(
            "删除 \(selection.count) 次训练？",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive, action: deleteSelectedSessions)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销")
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
        .onChange(of: selection) { _, _ in
            preparedShareURL = nil
        }
        .onChange(of: visibleSessionIDs) { _, visibleSessionIDs in
            selection.formIntersection(visibleSessionIDs)
            preparedShareURL = nil
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") {
                    endSelection()
                }
            }

            ToolbarItem(placement: .principal) {
                Text("\(selection.count) 项已选")
                    .font(.headline)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("全选", action: selectAllVisibleSessions)
                    .disabled(visibleSessionIDs.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("选择", action: beginSelection)
                    .disabled(visibleSessionIDs.isEmpty)
            }
        }
    }

    @ToolbarContentBuilder
    private var bottomToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) {
                if let preparedShareURL {
                    ShareLink(items: [preparedShareURL]) {
                        Label("分享 CSV", systemImage: "square.and.arrow.up")
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            endSelection(keepingPreparedShare: true)
                        }
                    )
                } else {
                    Button(action: prepareSelectedShare) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .disabled(selection.isEmpty)
                }

                Spacer()

                Button(role: .destructive, action: confirmDeleteSelectedSessions) {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    private func beginSelection() {
        preparedShareURL = nil
        editMode?.wrappedValue = .active
    }

    private func beginSelection(with sessionID: UUID) {
        beginSelection()
        selection.insert(sessionID)
    }

    private func endSelection(keepingPreparedShare: Bool = false) {
        selection.removeAll()
        editMode?.wrappedValue = .inactive

        if keepingPreparedShare == false {
            preparedShareURL = nil
        }
    }

    private func selectAllVisibleSessions() {
        selection = visibleSessionIDs
    }

    private func prepareSelectedShare() {
        do {
            preparedShareURL = try CSVExporter.exportFile(in: modelContext, sessionIDs: selection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmDeleteSelectedSessions() {
        guard selectedContainsOpenSession == false else {
            errorMessage = WorkoutSessionLifecycleError.cannotDeleteOpenSession.localizedDescription
            return
        }

        isShowingDeleteConfirmation = true
    }

    private func deleteSelectedSessions() {
        do {
            try WorkoutSessionLifecycle.deleteCompletedSessions(sessionIDs: selection, in: modelContext)
            endSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WorkoutHistoryDetailView: View {
    let sessionID: UUID

    @AppStorage(WeightUnit.storageKey) private var weightUnitRawValue = WeightUnit.kilograms.rawValue
    @Query private var sessions: [WorkoutSession]
    @Query private var sets: [WorkoutSet]

    private var session: WorkoutSession? {
        sessions.first { $0.id == sessionID }
    }

    private var weightUnit: WeightUnit {
        WeightUnit(rawValue: weightUnitRawValue) ?? .kilograms
    }

    private var weightUnitSelection: Binding<String> {
        Binding(
            get: { weightUnit.rawValue },
            set: { weightUnitRawValue = $0 }
        )
    }

    private var groups: [WorkoutHistoryExerciseGroup] {
        WorkoutHistoryData.exerciseGroups(for: sessionID, sets: sets)
    }

    var body: some View {
        List {
            if let session {
                Section {
                    Picker("重量单位", selection: weightUnitSelection) {
                        ForEach(WeightUnit.allCases, id: \.rawValue) { unit in
                            Text(unit.rawValue).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(DZColor.pump500)
                    .accessibilityIdentifier("history-detail-weight-unit-picker")
                }

                Section("训练") {
                    LabeledContent("模板", value: WorkoutHistoryData.templateName(for: session))
                    LabeledContent("开始", value: WorkoutHistoryDisplay.fullDateTimeText(for: session.startedAt, timeZoneIdentifier: session.timezoneIdentifier))
                    LabeledContent(
                        "结束",
                        value: session.endedAt.map {
                            WorkoutHistoryDisplay.fullDateTimeText(for: $0, timeZoneIdentifier: session.timezoneIdentifier)
                        } ?? "进行中"
                    )
                }

                ForEach(groups) { group in
                    Section(group.exerciseName) {
                        ForEach(group.sets) { set in
                            WorkoutHistorySetRow(set: set, unit: weightUnit)
                        }
                    }
                }
            }
        }
        .overlay {
            if session == nil {
                ContentUnavailableView(
                    "训练不存在",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("这次训练可能已经被删除。")
                )
            }
        }
        .dzScreenBackground()
        .navigationTitle(session.map { WorkoutHistoryData.templateName(for: $0) } ?? "训练详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkoutHistoryRowView: View {
    let row: WorkoutHistoryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
                .font(.body)
                .foregroundStyle(DZColor.ink900)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct WorkoutHistorySetRow: View {
    let set: WorkoutSet
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(WorkoutHistoryData.setTitle(for: set))
                    .foregroundStyle(DZColor.ink900)

                Spacer()

                Text(WorkoutHistoryDisplay.setValueText(weightKilograms: set.weight, reps: set.reps, unit: unit))
                    .dzNumeric(size: 15)
                    .foregroundStyle(DZColor.ink900)
            }

            HStack(spacing: 8) {
                if let rpe = set.rpe {
                    Text("RPE \(rpe)")
                }

                Text(WorkoutHistoryDisplay.timeText(for: set.completedAt, timeZoneIdentifier: set.session?.timezoneIdentifier))
            }
            .font(.caption)
            .foregroundStyle(DZColor.ink700)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        WorkoutHistoryView()
    }
    .modelContainer(
        for: [Exercise.self, Template.self, WorkoutSession.self, WorkoutSet.self],
        inMemory: true
    )
}
