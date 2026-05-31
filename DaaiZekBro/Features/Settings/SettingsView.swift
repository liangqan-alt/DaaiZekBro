import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var watchSubmissionRecords: [WatchSetSubmissionRecord]
    @State private var isShowingExportSheet = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                DZSection("训练", footer: "周期会按起始日期与时区循环推算未来安排。") {
                    NavigationLink {
                        TrainingScheduleView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .foregroundStyle(DZColor.pump500)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("训练安排")
                                    .foregroundStyle(DZColor.ink900)

                                Text("配置周期 · 查看未来 7 天")
                                    .font(.caption)
                                    .foregroundStyle(DZColor.ink700)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DZColor.fgFaint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("training-schedule-entry")
                }

                DZSection {
                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(DZColor.pump500)

                            Text("训练历史")
                                .foregroundStyle(DZColor.ink900)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DZColor.fgFaint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-history-button")
                }

                DZSection {
                    NavigationLink {
                        WatchSetSubmissionReviewView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "applewatch")
                                .foregroundStyle(DZColor.pump500)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Watch 需用户处理")
                                    .foregroundStyle(DZColor.ink900)

                                Text(watchSubmissionReviewSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(DZColor.ink700)
                            }

                            Spacer()

                            if unresolvedWatchSubmissionCount > 0 {
                                Text("\(unresolvedWatchSubmissionCount)")
                                    .font(DZFont.mono(size: 13, weight: .bold))
                                    .foregroundStyle(DZColor.fgOnPump)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(DZColor.skull500)
                                    .clipShape(Capsule())
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DZColor.fgFaint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch-submission-review-entry")
                }

                DZSection {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .foregroundStyle(DZColor.pump500)

                            Text("管理动作库")
                                .foregroundStyle(DZColor.ink900)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DZColor.fgFaint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exercise-library-entry")
                }

                DZSection(footer: "可按全部、最近日期或自定义日期范围导出训练 CSV。") {
                    Button {
                        exportURL = nil
                        isShowingExportSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.arrow.up")
                                .foregroundStyle(DZColor.pump500)

                            Text("导出 CSV")
                                .foregroundStyle(DZColor.ink900)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DZColor.fgFaint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("export-csv-button")
                }

                DZSection("负重口径") {
                    Text("统一记录杠面或机器显示的数字；哑铃记录单只重量，自重动作记录 0，负重自重动作记录所加负重。")
                        .foregroundStyle(DZColor.ink900)
                        .lineSpacing(2)
                        .padding(14)
                }

                DZSection("单侧动作") {
                    Text("单侧动作左右各记录一行，side 分别为 left 与 right；左右组号独立编号，双侧动作 side 留空。")
                        .foregroundStyle(DZColor.ink900)
                        .lineSpacing(2)
                        .padding(14)
                }
            }
            .padding(DZMetric.contentPadding)
        }
        .dzScreenBackground()
        .navigationTitle("设置")
        .sheet(isPresented: $isShowingExportSheet) {
            CSVExportSheet(
                exportURL: $exportURL,
                errorMessage: $errorMessage
            )
        }
        .alert(
            "导出失败",
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

    private var unresolvedWatchSubmissionCount: Int {
        watchSubmissionRecords.filter { $0.status == .needsUserAction }.count
    }

    private var watchSubmissionReviewSubtitle: String {
        if unresolvedWatchSubmissionCount == 0 {
            return "暂无待处理记录"
        }

        return "\(unresolvedWatchSubmissionCount) 条待归位或丢弃"
    }
}

private struct CSVExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [WorkoutSession]
    @Query private var sets: [WorkoutSet]
    @Binding var exportURL: URL?
    @Binding var errorMessage: String?
    @State private var selectedOption: CSVExportRangeOption = .full
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                    rangeSection
                    exportSection
                }
                .padding(DZMetric.contentPadding)
            }
            .dzScreenBackground()
            .navigationTitle("导出 CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedOption) { _, _ in
                clearPreparedExport()
            }
            .onChange(of: customStartDate) { _, _ in
                clearPreparedExport()
            }
            .onChange(of: customEndDate) { _, _ in
                clearPreparedExport()
            }
            .onChange(of: dataVersion) { _, _ in
                clearPreparedExport()
            }
        }
    }

    private var rangeSection: some View {
        DZSection("时间范围") {
            VStack(spacing: 0) {
                ForEach(CSVExportRangeOption.allCases) { option in
                    Button {
                        selectedOption = option
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(DZColor.ink900)

                            Spacer()

                            if selectedOption == option {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(DZColor.pump500)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option != CSVExportRangeOption.allCases.last {
                        DZDivider()
                    }
                }
            }
            .accessibilityIdentifier("csv-export-range-picker")

            if selectedOption == .custom {
                DZDivider()

                DatePicker("起始日期", selection: $customStartDate, displayedComponents: .date)
                    .foregroundStyle(DZColor.ink900)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("csv-export-start-date")

                DZDivider()

                DatePicker("结束日期", selection: $customEndDate, displayedComponents: .date)
                    .foregroundStyle(DZColor.ink900)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("csv-export-end-date")
            }
        }
    }

    private var exportSection: some View {
        DZSection(footer: exportFooterText) {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("分享 CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DZPrimaryButtonStyle())
                .padding(14)
                .accessibilityIdentifier("share-csv-link")
            } else {
                Button {
                    prepareExport()
                } label: {
                    Label("生成 CSV", systemImage: "doc.badge.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DZPrimaryButtonStyle())
                .disabled(exportDisabledReason != nil)
                .padding(14)
                .accessibilityIdentifier("generate-csv-button")
            }
        }
    }

    private var dataVersion: Int {
        sessions.count + sets.count
    }

    private var selectedRange: CSVExportRange {
        switch selectedOption {
        case .full:
            return .full
        case .last7Days:
            return .last7Days
        case .last30Days:
            return .last30Days
        case .custom:
            return .custom(startDate: customStartDate, endDate: customEndDate)
        }
    }

    private var summaryResult: Result<CSVExportSummary, Error> {
        Result {
            try CSVExporter.summary(in: modelContext, range: selectedRange)
        }
    }

    private var footerText: String {
        switch summaryResult {
        case .success(let summary):
            return "将导出 \(summary.sessionCount) 个 session · \(summary.setCount) 个组"
        case .failure(let error):
            if (error as? CSVExporterError) == .invalidDateRange {
                return "将导出 0 个 session · 0 个组"
            }

            return "无法读取该时间范围的训练"
        }
    }

    private var exportFooterText: String {
        if let exportDisabledReason {
            return "\(footerText)\n\(exportDisabledReason)"
        }

        return footerText
    }

    private var exportDisabledReason: String? {
        switch summaryResult {
        case .success(let summary):
            return summary.setCount == 0 ? CSVExporterError.noDataInRange.localizedDescription : nil
        case .failure(let error):
            if (error as? CSVExporterError) == .invalidDateRange {
                return CSVExporterError.invalidDateRange.localizedDescription
            }

            return error.localizedDescription
        }
    }

    private func prepareExport() {
        do {
            exportURL = try CSVExporter.exportFile(in: modelContext, range: selectedRange)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearPreparedExport() {
        exportURL = nil
    }
}

private enum CSVExportRangeOption: String, CaseIterable, Identifiable {
    case full
    case last7Days
    case last30Days
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .full:
            return "全部"
        case .last7Days:
            return "最近 7 天"
        case .last30Days:
            return "最近 30 天"
        case .custom:
            return "自定义"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(
        for: DaaiZekBroSchema.modelTypes,
        inMemory: true
    )
}
