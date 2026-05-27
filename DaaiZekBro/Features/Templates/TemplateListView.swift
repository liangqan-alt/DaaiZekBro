import SwiftData
import SwiftUI

struct TemplateListView: View {
    @Binding var path: [AppRoute]
    @Environment(\.modelContext) private var modelContext
    @Query private var templates: [Template]
    @Query private var sessions: [WorkoutSession]
    @Query private var sets: [WorkoutSet]
    @Query private var cycles: [TrainingCycle]
    @Query private var slots: [TrainingCycleSlot]
    @Query private var overrides: [TrainingDayOverride]
    @State private var pendingTemplateName: String?
    @State private var errorMessage: String?
    @State private var isEditingTemplates = false
    @State private var isShowingNameEditor = false
    @State private var editingTemplateID: PersistentIdentifier?
    @State private var pendingDeleteTemplateID: PersistentIdentifier?
    @State private var pendingDeleteTemplateName: String?
    @State private var isShowingDeleteWarning = false

    var body: some View {
        Group {
            if isEditingTemplates {
                editingContent
            } else {
                browsingContent
            }
        }
        .dzScreenBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isShowingNameEditor) {
            TemplateNameEditorView(templateID: editingTemplateID)
        }
        .onChange(of: isShowingNameEditor) { _, isPresented in
            if isPresented == false {
                editingTemplateID = nil
            }
        }
        .toolbar {
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
                todayPlanSection
                templateSection
                recentTrainingSection
            }
            .padding(DZMetric.contentPadding)
        }
        .accessibilityIdentifier("home-browsing-screen")
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
        .accessibilityIdentifier("template-editing-list")
    }

    @ViewBuilder
    private var todayPlanSection: some View {
        if let currentOpenSession {
            continueButton(for: currentOpenSession)
        } else {
            switch todayPlanCardResult {
            case .success(let card?):
                TodayPlanCardView(
                    card: card,
                    onOpenSchedule: openTrainingSchedule,
                    onStart: {
                        guard let template = card.startTemplate else { return }

                        startOrResolveConflict(for: template)
                    }
                )
            case .success(nil):
                EmptyView()
            case .failure(let error):
                TodayPlanErrorCard(errorMessage: error.localizedDescription)
            }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: DZMetric.space2) {
            HomeSectionHeader(title: "训练模板") {
                Button("编辑") {
                    withAnimation {
                        isEditingTemplates = true
                    }
                }
                .font(.body.weight(.medium))
                .foregroundStyle(DZColor.pump500)
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-template-edit-button")
            }

            if orderedTemplates.isEmpty {
                HomeEmptyState(
                    title: "还没有训练模板",
                    message: "点击「编辑」→「+」创建"
                )
                .accessibilityIdentifier("home-template-empty-state")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(orderedTemplates) { template in
                            DZTemplateCard(
                                name: template.name,
                                exerciseCount: exerciseCount(for: template),
                                colorHex: template.colorHex
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
                    .padding(.vertical, 4)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .accessibilityIdentifier("home-template-carousel")
            }
        }
    }

    private var recentTrainingSection: some View {
        VStack(alignment: .leading, spacing: DZMetric.space2) {
            HomeSectionHeader(title: "最近训练") {
                Button("全部 →") {
                    path.append(.workoutHistory)
                }
                .font(.body.weight(.medium))
                .foregroundStyle(DZColor.pump500)
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-recent-history-link")
            }

            let rows = recentTrainingRows

            if rows.isEmpty {
                HomeEmptyState(
                    title: "完成训练后会在这里显示最近记录",
                    message: nil
                )
                .accessibilityIdentifier("home-recent-empty-state")
            } else {
                HomeRecentTrainingList(rows: rows)
            }
        }
    }

    private var orderedTemplates: [Template] {
        TemplateCarouselViewData.orderedTemplates(templates)
    }

    private func exerciseCount(for template: Template) -> Int {
        TemplateCarouselViewData.exerciseCount(for: template)
    }

    private var recentTrainingRows: [WorkoutHistoryRow] {
        HomeRecentTrainingViewData.rows(
            sessions: sessions,
            sets: sets,
            now: AppLaunchConfiguration.now(),
            calendar: .current
        )
    }

    private var currentOpenSession: WorkoutSession? {
        sessions
            .filter { $0.endedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    private var todayPlanCardResult: Result<TrainingSchedulePresentation.TodayPlanCard?, Error> {
        _ = scheduleDataVersion

        return Result {
            try TrainingSchedulePresentation.todayCard(
                now: AppLaunchConfiguration.now(),
                in: modelContext
            )
        }
    }

    private var scheduleDataVersion: Int {
        let cycleVersion = cycles.reduce(0) { partialResult, cycle in
            partialResult
                + cycle.id.uuidString.count
                + Int(cycle.startDate.timeIntervalSince1970)
                + cycle.timezoneIdentifier.count
        }

        let slotVersion = slots.reduce(0) { partialResult, slot in
            partialResult
                + (slot.cycle?.id.uuidString.count ?? 0)
                + slot.orderIndex
                + slot.kind.rawValue.count
                + slot.templateStableID.count
                + (slot.template?.stableID.count ?? 0)
                + (slot.template?.name.count ?? 0)
                + (slot.template?.colorHex?.count ?? 0)
        }

        let overrideVersion = overrides.reduce(0) { partialResult, dayOverride in
            partialResult
                + (dayOverride.cycle?.id.uuidString.count ?? 0)
                + dayOverride.localDateKey.count
                + dayOverride.cycleDateKey.count
                + dayOverride.kind.rawValue.count
                + dayOverride.templateStableID.count
                + (dayOverride.template?.stableID.count ?? 0)
                + (dayOverride.template?.name.count ?? 0)
                + (dayOverride.template?.colorHex?.count ?? 0)
        }

        let sessionVersion = sessions.reduce(0) { partialResult, session in
            partialResult
                + session.id.uuidString.count
                + (session.template?.stableID.count ?? 0)
                + session.templateNameSnapshot.count
                + session.templateStableIDSnapshot.count
                + Int(session.startedAt.timeIntervalSince1970)
                + Int(session.endedAt?.timeIntervalSince1970 ?? 0)
        }

        let templateVersion = templates.reduce(0) { partialResult, template in
            partialResult
                + template.name.count
                + template.sortIndex
                + template.stableID.count
                + (template.colorHex?.count ?? 0)
        }

        return cycleVersion
            + slotVersion
            + overrideVersion
            + sessionVersion
            + templateVersion
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

    private func openTrainingSchedule() {
        path.append(TodayPlanCardRouteIntent.body)
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
        .accessibilityIdentifier("continue-workout-card")
    }

    private func startOrResolveConflict(for template: Template) {
        do {
            switch try WorkoutStartFlow.startOrConflict(
                for: template,
                in: modelContext,
                startedAt: AppLaunchConfiguration.now()
            ) {
            case .started(let session):
                path.append(.currentWorkout(sessionID: session.id))
            case .conflict:
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

            let newSession = try WorkoutSessionLifecycle.createSession(
                for: template,
                in: modelContext,
                startedAt: AppLaunchConfiguration.now()
            )
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

            let newSession = try WorkoutSessionLifecycle.createSession(
                for: template,
                in: modelContext,
                startedAt: AppLaunchConfiguration.now()
            )
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

enum TemplateCarouselViewData {
    static func orderedTemplates(_ templates: [Template]) -> [Template] {
        templates.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }

            return lhs.name < rhs.name
        }
    }

    static func exerciseCount(for template: Template) -> Int {
        let linkedExerciseCount = template.templateExercises.filter { $0.exercise != nil }.count

        return linkedExerciseCount == 0 ? template.exercises.count : linkedExerciseCount
    }
}

enum HomeRecentTrainingViewData {
    static let rowLimit = 3

    static func rows(
        sessions: [WorkoutSession],
        sets: [WorkoutSet],
        now: Date,
        calendar: Calendar
    ) -> [WorkoutHistoryRow] {
        let historyRows = WorkoutHistoryData.sections(
            sessions: sessions,
            sets: sets,
            now: now,
            calendar: calendar
        )
        .flatMap(\.rows)

        return Array(
            historyRows
                .filter { $0.summary.endedAt != nil }
                .sorted { $0.summary.startedAt > $1.summary.startedAt }
                .prefix(rowLimit)
        )
    }
}

enum TodayPlanCardRouteIntent {
    static let body = AppRoute.trainingSchedule
}

private struct TodayPlanCardView: View {
    let card: TrainingSchedulePresentation.TodayPlanCard
    let onOpenSchedule: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DZMetric.space3) {
            Button(action: onOpenSchedule) {
                VStack(alignment: .leading, spacing: DZMetric.space3) {
                    HStack(spacing: DZMetric.space2) {
                        Circle()
                            .fill(DZColor.templateColor(for: card.colorStyle))
                            .frame(width: 10, height: 10)
                            .opacity(card.colorStyle == .rest ? 0.55 : 1)

                        Text(card.colorStyle == .rest ? "今日" : "今日计划")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DZColor.bronze600)

                        Spacer(minLength: DZMetric.space2)

                        if let statusText = card.statusText {
                            TodayPlanStatusPill(text: statusText, colorStyle: card.colorStyle)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DZColor.fgFaint)
                    }

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DZColor.templateColor(for: card.colorStyle))
                        .frame(height: 4)
                        .opacity(card.colorStyle == .rest ? 0.45 : 1)

                    Text(card.titleText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(card.colorStyle == .invalid ? DZColor.ink700 : DZColor.ink900)
                        .strikethrough(card.colorStyle == .invalid, color: DZColor.templateInvalid)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let lastCompletionText = card.lastCompletionText {
                        Text(lastCompletionText)
                            .font(.caption)
                            .foregroundStyle(DZColor.ink700)
                    }

                    if let hintText = card.hintText {
                        Text(hintText)
                            .font(.caption)
                            .foregroundStyle(DZColor.ink700)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DZColor.cream200)
                            .clipShape(RoundedRectangle(cornerRadius: DZMetric.radiusSM, style: .continuous))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DZPressablePlainButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("today-plan-card-body")

            if card.showsStartButton {
                Button("开始训练", action: onStart)
                    .accessibilityIdentifier("today-plan-start-button")
                    .buttonStyle(DZPrimaryButtonStyle())
            }
        }
        .padding(14)
        .dzCardStyle()
    }

    private var accessibilityLabel: String {
        [
            "今日计划卡",
            card.titleText,
            card.statusText,
            card.hintText,
            card.lastCompletionText,
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }
}

private struct TodayPlanStatusPill: View {
    let text: String
    let colorStyle: TrainingSchedulePresentation.ColorStyle

    private var foreground: Color {
        if text == "✓ 已完成" {
            return DZColor.pr600
        }

        if colorStyle == .invalid {
            return DZColor.ink800
        }

        return DZColor.bronze700
    }

    private var background: Color {
        if text == "✓ 已完成" {
            return DZColor.pr100
        }

        if colorStyle == .invalid {
            return DZColor.invalidTint
        }

        return DZColor.statusNeutral
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
                        colorStyle == .invalid ? DZColor.templateInvalid.opacity(0.65) : Color.clear,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
    }
}

private struct TodayPlanErrorCard: View {
    let errorMessage: String

    var body: some View {
        Text("今日计划读取失败：\(errorMessage)")
            .font(.caption)
            .foregroundStyle(DZColor.ink700)
            .lineSpacing(2)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dzCardStyle()
            .accessibilityIdentifier("today-plan-error-card")
    }
}

private struct HomeSectionHeader<Action: View>: View {
    let title: String
    private let action: Action

    init(
        title: String,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(DZColor.ink900)

            Spacer(minLength: DZMetric.space3)

            action
        }
        .padding(.horizontal, DZMetric.sectionHeaderPadding)
    }
}

private struct HomeEmptyState: View {
    let title: String
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DZMetric.space1) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(DZColor.ink900)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DZColor.ink700)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dzCardStyle()
    }
}

private struct HomeRecentTrainingList: View {
    let rows: [WorkoutHistoryRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HomeRecentTrainingRow(
                    row: rows[index],
                    accessibilityIdentifier: "home-recent-row-\(index)"
                )

                if index < rows.index(before: rows.endIndex) {
                    DZDivider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dzCardStyle()
    }
}

private struct HomeRecentTrainingRow: View {
    let row: WorkoutHistoryRow
    let accessibilityIdentifier: String

    var body: some View {
        Text(row.title)
            .font(.body)
            .foregroundStyle(DZColor.ink900)
            .lineLimit(2)
            .accessibilityIdentifier(accessibilityIdentifier)
            .padding(.horizontal, DZMetric.rowHorizontalPadding)
            .padding(.vertical, DZMetric.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
