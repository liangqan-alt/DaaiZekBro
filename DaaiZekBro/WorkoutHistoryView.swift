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

    @Query private var sessions: [WorkoutSession]
    @Query private var sets: [WorkoutSet]

    private var session: WorkoutSession? {
        sessions.first { $0.id == sessionID }
    }

    private var groups: [WorkoutHistoryExerciseGroup] {
        WorkoutHistoryData.exerciseGroups(for: sessionID, sets: sets)
    }

    var body: some View {
        List {
            if let session {
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
                            WorkoutHistorySetRow(set: set)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(WorkoutHistoryData.setTitle(for: set))
                    .foregroundStyle(DZColor.ink900)

                Spacer()

                Text("\(WorkoutHistoryDisplay.weightText(set.weight)) kg x \(set.reps)")
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

struct WorkoutHistoryMonthSection: Identifiable, Equatable {
    let id: WorkoutHistoryMonth
    let rows: [WorkoutHistoryRow]

    var title: String {
        "\(id.year) 年 \(id.month) 月"
    }
}

struct WorkoutHistoryRow: Identifiable, Equatable {
    let summary: WorkoutHistorySessionSummary
    let showsStartTime: Bool
    let now: Date

    var id: UUID {
        summary.id
    }

    var title: String {
        WorkoutHistoryDisplay.listTitle(for: summary, showsStartTime: showsStartTime, now: now)
    }

}

struct WorkoutHistorySessionSummary: Identifiable, Equatable {
    let id: UUID
    let templateName: String
    let startedAt: Date
    let endedAt: Date?
    let timezoneIdentifier: String
    let setCount: Int
}

struct WorkoutHistoryMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    static func < (lhs: WorkoutHistoryMonth, rhs: WorkoutHistoryMonth) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }

        return lhs.month < rhs.month
    }
}

struct WorkoutHistoryExerciseGroup: Identifiable {
    let id: String
    let exerciseName: String
    let sets: [WorkoutSet]
}

enum WorkoutHistoryData {
    static func sections(
        sessions: [WorkoutSession],
        sets: [WorkoutSet],
        now: Date,
        calendar: Calendar
    ) -> [WorkoutHistoryMonthSection] {
        sections(for: summaries(sessions: sessions, sets: sets), now: now, calendar: calendar)
    }

    static func sections(
        for summaries: [WorkoutHistorySessionSummary],
        now: Date,
        calendar: Calendar
    ) -> [WorkoutHistoryMonthSection] {
        let orderedSummaries = summaries.sorted { $0.startedAt > $1.startedAt }
        let dayCounts = Dictionary(grouping: orderedSummaries) { summary in
            dayKey(for: summary)
        }
            .mapValues(\.count)
        let groupedByMonth = Dictionary(grouping: orderedSummaries) { summary in
            month(for: summary, calendar: calendar)
        }

        return groupedByMonth
            .keys
            .sorted(by: >)
            .map { month in
                let rows = (groupedByMonth[month] ?? [])
                    .sorted { $0.startedAt > $1.startedAt }
                    .map { summary in
                        WorkoutHistoryRow(
                            summary: summary,
                            showsStartTime: dayCounts[dayKey(for: summary), default: 0] > 1,
                            now: now
                        )
                    }

                return WorkoutHistoryMonthSection(id: month, rows: rows)
            }
    }

    static func summaries(sessions: [WorkoutSession], sets: [WorkoutSet]) -> [WorkoutHistorySessionSummary] {
        let setsBySessionID = Dictionary(grouping: sets.compactMap { set -> (UUID, WorkoutSet)? in
            guard let sessionID = set.session?.id else {
                return nil
            }

            return (sessionID, set)
        }, by: \.0)

        return sessions.compactMap { session in
            let setCount = setsBySessionID[session.id]?.count ?? 0

            guard setCount > 0 else {
                return nil
            }

            return WorkoutHistorySessionSummary(
                id: session.id,
                templateName: templateName(for: session),
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                timezoneIdentifier: session.timezoneIdentifier,
                setCount: setCount
            )
        }
    }

    static func exerciseGroups(for sessionID: UUID, sets: [WorkoutSet]) -> [WorkoutHistoryExerciseGroup] {
        let orderedSets = sets
            .filter { $0.session?.id == sessionID }
            .sorted { lhs, rhs in
                areSetsInDisplayOrder(lhs, rhs)
            }
        var groups: [WorkoutHistoryExerciseGroup] = []

        for set in orderedSets {
            let exerciseName = exerciseName(for: set)
            let groupID = "\(set.exerciseOrderIndex)-\(exerciseName)"

            if let index = groups.firstIndex(where: { $0.id == groupID }) {
                var updatedSets = groups[index].sets
                updatedSets.append(set)
                groups[index] = WorkoutHistoryExerciseGroup(id: groupID, exerciseName: exerciseName, sets: updatedSets)
            } else {
                groups.append(WorkoutHistoryExerciseGroup(id: groupID, exerciseName: exerciseName, sets: [set]))
            }
        }

        return groups
    }

    static func templateName(for session: WorkoutSession) -> String {
        if let templateName = session.template?.name, templateName.isEmpty == false {
            return templateName
        }

        return session.templateNameSnapshot.isEmpty ? "未命名训练" : session.templateNameSnapshot
    }

    static func exerciseName(for set: WorkoutSet) -> String {
        if set.exerciseNameSnapshot.isEmpty == false {
            return set.exerciseNameSnapshot
        }

        return set.exercise?.name ?? "未命名动作"
    }

    static func setTitle(for set: WorkoutSet) -> String {
        let sideText = set.side.map { " · \(WorkoutHistoryDisplay.sideText($0))" } ?? ""

        return "第 \(set.setIndex) 组\(sideText)"
    }

    private static func month(
        for summary: WorkoutHistorySessionSummary,
        calendar: Calendar
    ) -> WorkoutHistoryMonth {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: summary.timezoneIdentifier) ?? calendar.timeZone
        let components = calendar.dateComponents([.year, .month], from: summary.startedAt)

        return WorkoutHistoryMonth(year: components.year ?? 1, month: components.month ?? 1)
    }

    private static func dayKey(for summary: WorkoutHistorySessionSummary) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: summary.timezoneIdentifier) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: summary.startedAt)

        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(calendar.timeZone.identifier)"
    }

    private static func areSetsInDisplayOrder(_ lhs: WorkoutSet, _ rhs: WorkoutSet) -> Bool {
        if lhs.exerciseOrderIndex != rhs.exerciseOrderIndex {
            return lhs.exerciseOrderIndex < rhs.exerciseOrderIndex
        }

        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt < rhs.completedAt
        }

        if lhs.setIndex != rhs.setIndex {
            return lhs.setIndex < rhs.setIndex
        }

        return (lhs.side?.rawValue ?? "") < (rhs.side?.rawValue ?? "")
    }
}

enum WorkoutHistoryDisplay {
    static func listTitle(
        for summary: WorkoutHistorySessionSummary,
        showsStartTime: Bool,
        now: Date
    ) -> String {
        let dateText = dateText(for: summary.startedAt, timeZoneIdentifier: summary.timezoneIdentifier)
        let timeText = showsStartTime ? " \(timeText(for: summary.startedAt, timeZoneIdentifier: summary.timezoneIdentifier))" : ""
        let statusText = summary.endedAt == nil ? " (进行中)" : ""
        let durationText = durationText(from: summary.startedAt, to: summary.endedAt ?? now)

        return "\(dateText)\(timeText) · \(summary.templateName)\(statusText) · \(summary.setCount)组 · \(durationText)"
    }

    static func fullDateTimeText(for date: Date, timeZoneIdentifier: String) -> String {
        format(date, timeZoneIdentifier: timeZoneIdentifier, dateFormat: "yyyy-MM-dd HH:mm")
    }

    static func timeText(for date: Date, timeZoneIdentifier: String?) -> String {
        format(date, timeZoneIdentifier: timeZoneIdentifier, dateFormat: "HH:mm")
    }

    static func weightText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 1
        formatter.maximumFractionDigits = 1

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func sideText(_ side: Side) -> String {
        switch side {
        case .left:
            return "左"
        case .right:
            return "右"
        }
    }

    private static func dateText(for date: Date, timeZoneIdentifier: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayIndex = max(1, min(7, calendar.component(.weekday, from: date))) - 1
        let dayText = format(date, timeZoneIdentifier: timeZoneIdentifier, dateFormat: "yyyy-MM-dd")

        return "\(dayText) (\(weekdaySymbols[weekdayIndex]))"
    }

    private static func durationText(from startDate: Date, to endDate: Date) -> String {
        let elapsedMinutes = max(0, Int(endDate.timeIntervalSince(startDate)) / 60)
        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private static func format(_ date: Date, timeZoneIdentifier: String?, dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        formatter.dateFormat = dateFormat

        return formatter.string(from: date)
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
