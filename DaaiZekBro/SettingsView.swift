import SwiftUI
import SwiftData

struct SettingsView: View {
    @State private var isShowingExportSheet = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    exportURL = nil
                    isShowingExportSheet = true
                } label: {
                    Label("导出 CSV", systemImage: "doc.badge.arrow.up")
                }
                .accessibilityIdentifier("export-csv-button")
            } footer: {
                Text("可按全部、最近日期或自定义日期范围导出训练 CSV。")
            }

            Section("负重口径") {
                Text("统一记录杠面或机器显示的数字；哑铃记录单只重量，自重动作记录 0，负重自重动作记录所加负重。")
            }

            Section("单侧动作") {
                Text("单侧动作左右各记录一行，side 分别为 left 与 right；左右组号独立编号，双侧动作 side 留空。")
            }
        }
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
            List {
                Section("时间范围") {
                    Picker("时间范围", selection: $selectedOption) {
                        ForEach(CSVExportRangeOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("csv-export-range-picker")

                    if selectedOption == .custom {
                        DatePicker("起始日期", selection: $customStartDate, displayedComponents: .date)
                            .accessibilityIdentifier("csv-export-start-date")
                        DatePicker("结束日期", selection: $customEndDate, displayedComponents: .date)
                            .accessibilityIdentifier("csv-export-end-date")
                    }
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("分享 CSV", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("share-csv-link")
                    } else {
                        Button {
                            prepareExport()
                        } label: {
                            Label("生成 CSV", systemImage: "doc.badge.arrow.up")
                        }
                        .disabled(exportDisabledReason != nil)
                        .accessibilityIdentifier("generate-csv-button")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(footerText)

                        if let exportDisabledReason {
                            Text(exportDisabledReason)
                        }
                    }
                }
            }
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
        for: [Exercise.self, Template.self, WorkoutSession.self, WorkoutSet.self],
        inMemory: true
    )
}
