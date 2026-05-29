import SwiftData
import SwiftUI

struct TrainingScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var cycles: [TrainingCycle]
    @Query private var slots: [TrainingCycleSlot]
    @Query private var overrides: [TrainingDayOverride]
    @Query private var sessions: [WorkoutSession]
    @Query private var templates: [Template]
    @State private var editorPresentation: TrainingCycleEditorPresentation?
    @State private var selectedDay: TrainingScheduleDayNavigation?
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var activeCycle: TrainingCycle? {
        cycles.first
    }

    private var weekResult: Result<TrainingSchedulePresentation.Week, Error> {
        let data = TrainingScheduleDataSnapshot(
            cycles: cycles,
            slots: slots,
            overrides: overrides,
            sessions: sessions,
            templates: templates
        )

        return Result {
            try TrainingSchedulePresentation.week(now: AppLaunchConfiguration.now(), data: data)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                switch weekResult {
                case .success(let week):
                    if week.hasCycle {
                        if let summary = week.summary {
                            TrainingScheduleSummarySection(
                                summary: summary,
                                onDelete: { isConfirmingDelete = true }
                            )
                        }

                        TrainingScheduleWeekSection(days: week.days, onSelectDay: openDayDetail)
                    } else {
                        TrainingScheduleEmptyState {
                            presentCreateCycle()
                        }
                    }
                case .failure(let error):
                    ContentUnavailableView(
                        "训练安排读取失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                }
            }
            .padding(DZMetric.contentPadding)
        }
        .accessibilityIdentifier("training-schedule-screen")
        .dzScreenBackground()
        .navigationTitle("训练安排")
        .navigationDestination(item: $selectedDay) { day in
            TrainingScheduleDayDetailView(date: day.date, localDateKey: day.localDateKey)
        }
        .toolbar {
            if activeCycle != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("配置") {
                        Button("编辑周期") {
                            presentEditCycle()
                        }

                        Button("新建周期") {
                            presentCreateCycle()
                        }

                        Button("删除周期", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                    .accessibilityIdentifier("training-schedule-config-menu")
                }
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            NavigationStack {
                TrainingCycleEditorView(cycleID: presentation.cycleID)
            }
        }
        .confirmationDialog(
            "删除训练周期？",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除并清除覆盖", role: .destructive, action: deleteActiveCycle)
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前周期，并同时清除所有单日覆盖记录。已记录的训练 session 不会被删除。")
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

    private func presentCreateCycle() {
        if activeCycle != nil {
            errorMessage = TrainingScheduleEngineError.activeCycleAlreadyExists.localizedDescription
            return
        }

        editorPresentation = TrainingCycleEditorPresentation(cycleID: nil)
    }

    private func presentEditCycle() {
        guard let activeCycle else {
            presentCreateCycle()
            return
        }

        editorPresentation = TrainingCycleEditorPresentation(cycleID: activeCycle.persistentModelID)
    }

    private func openDayDetail(_ day: TrainingSchedulePresentation.Day) {
        selectedDay = TrainingScheduleDayNavigation(date: day.date, localDateKey: day.localDateKey)
    }

    private func deleteActiveCycle() {
        guard let activeCycle else { return }

        do {
            try TrainingScheduleEngine.deleteCycle(activeCycle, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TrainingScheduleDayNavigation: Hashable, Identifiable {
    let date: Date
    let localDateKey: String

    var id: String {
        localDateKey
    }
}

private struct TrainingScheduleSummarySection: View {
    let summary: TrainingSchedulePresentation.CycleSummary
    let onDelete: () -> Void

    var body: some View {
        DZSection("当前周期") {
            VStack(alignment: .leading, spacing: DZMetric.space3) {
                HStack(alignment: .center, spacing: DZMetric.space3) {
                    Text(summary.text)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DZColor.ink900)

                    Spacer()

                    HStack(spacing: 5) {
                        ForEach(Array(summary.colorStyles.enumerated()), id: \.offset) { _, style in
                            Circle()
                                .fill(DZColor.templateColor(for: style))
                                .frame(width: 9, height: 9)
                                .opacity(style == .rest ? 0.55 : 1)
                        }
                    }
                }

                DZDivider()

                Button(role: .destructive, action: onDelete) {
                    Label("删除周期", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DZDestructiveButtonStyle(fullWidth: true))
                .accessibilityIdentifier("training-cycle-delete-button")
            }
            .padding(14)
        }
    }
}

private struct TrainingScheduleWeekSection: View {
    let days: [TrainingSchedulePresentation.Day]
    let onSelectDay: (TrainingSchedulePresentation.Day) -> Void

    var body: some View {
        DZSection("未来 7 天") {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button {
                        onSelectDay(day)
                    } label: {
                        TrainingScheduleDayRow(day: day)
                    }
                    .buttonStyle(DZPressablePlainButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(day.isToday ? "今天" : day.weekdayText) \(day.dateText) \(day.title)")
                    .accessibilityIdentifier("training-schedule-day-\(day.localDateKey)")

                    if index != days.count - 1 {
                        DZDivider()
                    }
                }
            }
            .accessibilityIdentifier("training-schedule-week-list")
        }
    }
}

private struct TrainingScheduleDayRow: View {
    let day: TrainingSchedulePresentation.Day

    private var pillText: String? {
        day.statusText ?? (day.isInvalidPlan ? "计划已失效" : nil)
    }

    var body: some View {
        HStack(alignment: .center, spacing: DZMetric.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.isToday ? "今天" : day.weekdayText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(day.isToday ? DZColor.pump600 : DZColor.ink700)

                Text(day.dateText)
                    .dzNumeric(size: 14, weight: .semibold)
                    .foregroundStyle(DZColor.ink700)
            }
            .frame(width: 44, alignment: .leading)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(DZColor.templateColor(for: day.colorStyle))
                .frame(width: 4, height: 42)
                .opacity(day.colorStyle == .rest ? 0.55 : 1)

            Text(day.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(day.isInvalidPlan ? DZColor.ink700 : DZColor.ink900)
                .strikethrough(day.isInvalidPlan, color: DZColor.templateInvalid)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: DZMetric.space2)

            if let pillText {
                TrainingScheduleStatusPill(text: pillText, status: day.status, isInvalidPlan: day.isInvalidPlan)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DZColor.fgFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(day.isToday ? DZColor.pump100.opacity(0.55) : Color.clear)
        .overlay(alignment: .leading) {
            if day.isToday {
                Rectangle()
                    .fill(DZColor.pump500)
                    .frame(width: 3)
            }
        }
    }
}

private struct TrainingScheduleStatusPill: View {
    let text: String
    let status: TrainingScheduleCompletionStatus
    let isInvalidPlan: Bool

    private var foreground: Color {
        switch status {
        case .completed:
            DZColor.pr600
        case .completedWithDeletedPlanTemplate:
            DZColor.ink800
        case .none where isInvalidPlan:
            DZColor.ink700
        default:
            DZColor.bronze700
        }
    }

    private var background: Color {
        switch status {
        case .completed:
            DZColor.pr100
        case .completedWithDeletedPlanTemplate:
            DZColor.invalidTint
        case .none where isInvalidPlan:
            DZColor.invalidTint
        default:
            DZColor.statusNeutral
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        isInvalidPlan ? DZColor.templateInvalid.opacity(0.65) : Color.clear,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
    }
}

struct TrainingScheduleDayDetailView: View {
    let date: Date
    let localDateKey: String

    @Environment(\.modelContext) private var modelContext
    @Query private var cycles: [TrainingCycle]
    @Query private var slots: [TrainingCycleSlot]
    @Query private var overrides: [TrainingDayOverride]
    @Query private var sessions: [WorkoutSession]
    @Query private var templates: [Template]
    @State private var isShowingTemplatePicker = false
    @State private var errorMessage: String?

    private var orderedTemplates: [Template] {
        templates.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var detailResult: Result<TrainingScheduleDayDetailState, Error> {
        let data = TrainingScheduleDataSnapshot(
            cycles: cycles,
            slots: slots,
            overrides: overrides,
            sessions: sessions,
            templates: templates
        )

        return Result {
            guard let cycle = data.activeCycle else {
                throw TrainingScheduleDayDetailError.noActiveCycle
            }

            let plan = try data.plan(for: date, cycle: cycle)
            let status = try data.completionStatus(for: plan)
            let availability = try data.overrideAvailability(
                for: date,
                cycle: cycle,
                now: AppLaunchConfiguration.now()
            )

            return TrainingScheduleDayDetailState(
                cycle: cycle,
                plan: plan,
                status: status,
                availability: availability
            )
        }
    }

    var body: some View {
        Group {
            switch detailResult {
            case .success(let state):
                detailContent(state)
            case .failure(let error):
                ContentUnavailableView(
                    "训练日读取失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .accessibilityIdentifier("training-schedule-day-detail")
        .dzScreenBackground()
        .navigationTitle("训练日详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingTemplatePicker) {
            TrainingDayTemplatePickerView(
                templates: orderedTemplates,
                onSelect: setTemplateOverride
            )
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

    private func detailContent(_ state: TrainingScheduleDayDetailState) -> some View {
        let actionsAreAvailable = state.availability == .available
        let resetIsEnabled = actionsAreAvailable && state.plan.source == .override

        return ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                DZSection("当前计划") {
                    VStack(spacing: 0) {
                        DZInfoRow("日期", value: state.plan.localDateKey)
                        DZDivider()
                        DZInfoRow("当前计划", value: titleText(for: state.plan))
                        DZDivider()
                        DZInfoRow("来源", value: sourceText(for: state.plan.source))
                        DZDivider()
                        DZInfoRow("状态", value: statusText(for: state.status, plan: state.plan))
                    }
                }

                DZSection("覆盖操作") {
                    VStack(alignment: .leading, spacing: DZMetric.space3) {
                        if let unavailableMessage = state.availability.unavailableMessage {
                            Text(unavailableMessage)
                                .font(.caption)
                                .foregroundStyle(DZColor.ink700)
                                .lineSpacing(2)
                                .accessibilityIdentifier("training-day-override-locked-message")
                        }

                        Button {
                            isShowingTemplatePicker = true
                        } label: {
                            Label("覆盖为其他模板", systemImage: "square.grid.2x2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DZSecondaryButtonStyle(fullWidth: true))
                        .disabled(actionsAreAvailable == false || orderedTemplates.isEmpty)
                        .accessibilityIdentifier("training-day-override-template-button")

                        Button {
                            setRestOverride(state.cycle)
                        } label: {
                            Label("覆盖为休息日", systemImage: "pause.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DZSecondaryButtonStyle(fullWidth: true))
                        .disabled(actionsAreAvailable == false)
                        .accessibilityIdentifier("training-day-override-rest-button")

                        Button {
                            resetOverride(state.cycle)
                        } label: {
                            Label("重置为周期默认", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(DZSecondaryButtonStyle(fullWidth: true))
                        .disabled(resetIsEnabled == false)
                        .accessibilityIdentifier("training-day-reset-override-button")
                    }
                    .padding(14)
                }
            }
            .padding(DZMetric.contentPadding)
        }
        .accessibilityIdentifier("training-schedule-day-detail")
    }

    private func setTemplateOverride(_ template: Template) {
        do {
            try TrainingScheduleEngine.setOverride(
                for: date,
                cycle: try activeCycle(),
                kind: .workout,
                template: template,
                now: AppLaunchConfiguration.now(),
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setRestOverride(_ cycle: TrainingCycle) {
        do {
            try TrainingScheduleEngine.setOverride(
                for: date,
                cycle: cycle,
                kind: .rest,
                template: nil,
                now: AppLaunchConfiguration.now(),
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetOverride(_ cycle: TrainingCycle) {
        do {
            try TrainingScheduleEngine.resetOverride(
                for: date,
                cycle: cycle,
                now: AppLaunchConfiguration.now(),
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activeCycle() throws -> TrainingCycle {
        guard let cycle = cycles.first else {
            throw TrainingScheduleDayDetailError.noActiveCycle
        }

        return cycle
    }

    private func titleText(for plan: TrainingScheduleDayPlan) -> String {
        if plan.isInvalidPlan {
            return "计划已失效"
        }

        if plan.isRestDay {
            return "休息"
        }

        return plan.template?.name ?? "计划已失效"
    }

    private func sourceText(for source: TrainingSchedulePlanSource) -> String {
        switch source {
        case .cycle:
            return "周期默认"
        case .override:
            return "手动覆盖"
        }
    }

    private func statusText(
        for status: TrainingScheduleCompletionStatus,
        plan: TrainingScheduleDayPlan
    ) -> String {
        switch status {
        case .none:
            return plan.isRestDay ? "无训练记录" : "未完成"
        case .completed:
            return "✓ 已完成"
        case .completedWithNonPlanTemplate:
            return "✓ 已完成（非计划模板）"
        case .completedWithDeletedPlanTemplate:
            return "✓ 已完成（计划模板已删除）"
        case .unscheduledWorkout:
            return "计划外训练"
        }
    }
}

private struct TrainingDayTemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let templates: [Template]
    let onSelect: (Template) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "暂无模板",
                        systemImage: "square.grid.2x2",
                        description: Text("请先创建训练模板。")
                    )
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                onSelect(template)
                                dismiss()
                            } label: {
                                HStack(spacing: DZMetric.space3) {
                                    Circle()
                                        .fill(templateColor(for: template))
                                        .frame(width: 10, height: 10)

                                    Text(template.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(DZColor.ink900)

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("training-day-template-\(template.name)")
                        }
                        .listRowBackground(DZColor.cream50)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .accessibilityIdentifier("training-day-override-template-picker")
            .dzScreenBackground()
            .navigationTitle("选择模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func templateColor(for template: Template) -> Color {
        guard let colorHex = template.colorHex,
              let color = Color(hexString: colorHex) else {
            return DZColor.templateEmpty
        }

        return color
    }
}

private struct TrainingScheduleDayDetailState {
    let cycle: TrainingCycle
    let plan: TrainingScheduleDayPlan
    let status: TrainingScheduleCompletionStatus
    let availability: TrainingScheduleOverrideAvailability
}

private extension TrainingScheduleOverrideAvailability {
    var unavailableMessage: String? {
        switch self {
        case .available:
            return nil
        case .locked(.completedPlan):
            return "当天已按计划完成训练，覆盖操作不可用"
        case .locked(.historicalDate):
            return "历史日期不能覆盖"
        }
    }
}

private enum TrainingScheduleDayDetailError: LocalizedError {
    case noActiveCycle

    var errorDescription: String? {
        switch self {
        case .noActiveCycle:
            return "当前没有训练周期"
        }
    }
}

private struct TrainingScheduleEmptyState: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: DZMetric.space4) {
            Image(systemName: "calendar")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(DZColor.pump500)

            VStack(spacing: DZMetric.space2) {
                Text("还没有训练周期")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DZColor.ink900)

                Text("配置一个滚动周期（如 PPL 3 练 1 休），这里会自动显示今天起 7 天的安排。")
                    .font(.body)
                    .foregroundStyle(DZColor.ink700)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button(action: onCreate) {
                Text("配置训练周期")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DZPrimaryButtonStyle())
            .accessibilityIdentifier("training-schedule-create-button")
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .dzCardStyle()
        .accessibilityIdentifier("training-schedule-empty-state")
    }
}

private struct TrainingCycleEditorPresentation: Identifiable {
    let cycleID: PersistentIdentifier?

    var id: String {
        cycleID.map { "\($0)" } ?? "new"
    }
}

private struct TrainingCycleEditorView: View {
    let cycleID: PersistentIdentifier?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var cycles: [TrainingCycle]
    @Query private var slots: [TrainingCycleSlot]
    @Query private var templates: [Template]
    @State private var startDate = Date()
    @State private var drafts: [TrainingCycleSlotDraftState] = []
    @State private var editMode: EditMode = .active
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false

    private var isNewCycle: Bool {
        cycleID == nil
    }

    private var cycle: TrainingCycle? {
        guard let cycleID else { return nil }

        return cycles.first { $0.persistentModelID == cycleID }
    }

    private var orderedTemplates: [Template] {
        templates.sorted {
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }

            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section("起始日期") {
                DatePicker("起始日期", selection: $startDate, displayedComponents: .date)

                Text("时区 \(timezoneIdentifier)")
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
            }

            Section {
                ForEach($drafts) { $draft in
                    TrainingCycleSlotDraftRow(
                        draft: $draft,
                        templates: orderedTemplates
                    )
                }
                .onMove(perform: moveDrafts)
                .onDelete(perform: removeDrafts)

                Button {
                    addWorkoutSlot()
                } label: {
                    Label("添加训练模板", systemImage: "plus.circle")
                }
                .disabled(orderedTemplates.isEmpty)

                Button {
                    drafts.append(TrainingCycleSlotDraftState(kind: .rest, templateID: nil))
                } label: {
                    Label("添加休息日", systemImage: "plus.circle")
                }
            } header: {
                Text("槽位序列 · \(drafts.count) 个")
            } footer: {
                Text("至少一个训练模板；已覆盖某天的安排不受周期改动影响。")
            }

            if cycle != nil {
                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("删除训练周期", systemImage: "trash")
                    }
                    .accessibilityIdentifier("training-cycle-delete-button")
                } footer: {
                    Text("删除后将同时清除所有单日覆盖记录。")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .dzScreenBackground()
        .navigationTitle(isNewCycle ? "新建周期" : "编辑周期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(isNewCycle ? "完成" : "保存", action: save)
                    .accessibilityIdentifier("training-cycle-save-button")
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: cycleID) { _, _ in
            didLoad = false
            loadIfNeeded()
        }
        .confirmationDialog(
            "删除训练周期？",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除并清除覆盖", role: .destructive, action: deleteCycle)
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前周期，并同时清除所有单日覆盖记录。已记录的训练 session 不会被删除。")
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

    private var timezoneIdentifier: String {
        cycle?.timezoneIdentifier ?? TimeZone.current.identifier
    }

    private func loadIfNeeded() {
        guard didLoad == false else { return }
        didLoad = true

        if let cycle {
            startDate = cycle.startDate
            drafts = slots
                .filter { $0.cycle?.id == cycle.id }
                .sorted { $0.orderIndex < $1.orderIndex }
                .map {
                    TrainingCycleSlotDraftState(
                        kind: $0.kind,
                        templateID: $0.template?.persistentModelID,
                        templateStableID: $0.templateStableID
                    )
                }
            return
        }

        startDate = Date()
        drafts = orderedTemplates.map {
            TrainingCycleSlotDraftState(kind: .workout, templateID: $0.persistentModelID)
        }

        if drafts.isEmpty {
            drafts = [TrainingCycleSlotDraftState(kind: .rest, templateID: nil)]
        }
    }

    private func addWorkoutSlot() {
        guard let template = orderedTemplates.first else { return }

        drafts.append(TrainingCycleSlotDraftState(kind: .workout, templateID: template.persistentModelID))
    }

    private func moveDrafts(from source: IndexSet, to destination: Int) {
        drafts.move(fromOffsets: source, toOffset: destination)
    }

    private func removeDrafts(at offsets: IndexSet) {
        drafts.remove(atOffsets: offsets)
    }

    private func save() {
        do {
            let slotDrafts = try drafts.map { draft in
                try draft.slotDraft(templates: orderedTemplates)
            }

            if let cycle {
                try TrainingScheduleEngine.updateCycle(
                    cycle,
                    startDate: startDate,
                    slots: slotDrafts,
                    in: modelContext
                )
            } else {
                _ = try TrainingScheduleEngine.createCycle(
                    startDate: startDate,
                    timezoneIdentifier: TimeZone.current.identifier,
                    slots: slotDrafts,
                    in: modelContext
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCycle() {
        guard let cycle else { return }

        do {
            try TrainingScheduleEngine.deleteCycle(cycle, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TrainingCycleSlotDraftRow: View {
    @Binding var draft: TrainingCycleSlotDraftState
    let templates: [Template]

    var body: some View {
        VStack(alignment: .leading, spacing: DZMetric.space2) {
            Picker("类型", selection: $draft.kind) {
                Text("训练").tag(TrainingPlanEntryKind.workout)
                Text("休息").tag(TrainingPlanEntryKind.rest)
            }
            .pickerStyle(.segmented)

            if draft.kind == .workout {
                Picker("模板", selection: $draft.templateID) {
                    if draft.isInvalidWorkoutSlot {
                        Text("计划已失效").tag(Optional<PersistentIdentifier>.none)
                    }

                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.persistentModelID))
                    }
                }
            } else {
                Text("休息")
                    .foregroundStyle(DZColor.ink700)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: draft.kind) { _, newKind in
            if newKind == .rest {
                draft.templateID = nil
                draft.templateStableID = ""
            } else if draft.templateID == nil {
                selectFirstTemplate()
            }
        }
        .onChange(of: draft.templateID) { _, newTemplateID in
            updateStableID(for: newTemplateID)
        }
    }

    private func selectFirstTemplate() {
        guard let template = templates.first else { return }

        draft.templateID = template.persistentModelID
        draft.templateStableID = template.stableID
    }

    private func updateStableID(for templateID: PersistentIdentifier?) {
        guard draft.kind == .workout else {
            draft.templateStableID = ""
            return
        }

        if let templateID,
           let template = templates.first(where: { $0.persistentModelID == templateID }) {
            draft.templateStableID = template.stableID
        } else if draft.isInvalidWorkoutSlot == false {
            draft.templateStableID = ""
        }
    }
}

private struct TrainingCycleSlotDraftState: Identifiable {
    let id = UUID()
    var kind: TrainingPlanEntryKind
    var templateID: PersistentIdentifier?
    var templateStableID = ""

    var isInvalidWorkoutSlot: Bool {
        kind == .workout && templateID == nil && templateStableID.isEmpty == false
    }

    func slotDraft(templates: [Template]) throws -> TrainingScheduleSlotDraft {
        switch kind {
        case .rest:
            return TrainingScheduleSlotDraft(kind: .rest)
        case .workout:
            guard let templateID else {
                guard templateStableID.isEmpty == false else {
                    throw TrainingScheduleEngineError.invalidWorkoutSlotTemplate
                }

                return TrainingScheduleSlotDraft(kind: .workout, templateStableID: templateStableID)
            }

            guard let template = templates.first(where: { $0.persistentModelID == templateID }) else {
                throw TrainingScheduleEngineError.invalidWorkoutSlotTemplate
            }

            return TrainingScheduleSlotDraft(kind: .workout, template: template)
        }
    }
}

#Preview {
    NavigationStack {
        TrainingScheduleView()
    }
    .modelContainer(
        for: DaaiZekBroSchema.modelTypes,
        inMemory: true
    )
}
