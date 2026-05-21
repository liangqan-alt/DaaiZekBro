import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    prepareExport()
                } label: {
                    Label("导出 CSV", systemImage: "doc.badge.arrow.up")
                }
                .accessibilityIdentifier("export-csv-button")

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("分享 CSV", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("share-csv-link")
                }
            } footer: {
                Text("文件会导出为 gym_log_YYYY-MM-DD.csv。")
            }

            Section("负重口径") {
                Text("统一记录杠面或机器显示的数字；哑铃记录单只重量，自重动作记录 0，负重自重动作记录所加负重。")
            }

            Section("单侧动作") {
                Text("单侧动作左右各记录一行，side 分别为 left 与 right；左右组号独立编号，双侧动作 side 留空。")
            }
        }
        .navigationTitle("设置")
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

    private func prepareExport() {
        do {
            exportURL = try CSVExporter.exportFile(in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
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
