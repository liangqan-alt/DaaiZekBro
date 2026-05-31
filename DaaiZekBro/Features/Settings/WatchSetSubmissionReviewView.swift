import SwiftData
import SwiftUI

struct WatchSetSubmissionReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchSetSubmissionRecord.completedAt, order: .reverse)
    private var records: [WatchSetSubmissionRecord]
    @State private var relocatingClientSubmissionID: String?
    @State private var pendingDiscardClientSubmissionID: String?
    @State private var errorMessage: String?

    private var unresolvedRecords: [WatchSetSubmissionRecord] {
        records.filter { $0.status == .needsUserAction }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                if unresolvedRecords.isEmpty {
                    DZSection {
                        Text("当前没有需要处理的 Watch 记录。")
                            .foregroundStyle(DZColor.ink900)
                            .padding(14)
                    }
                } else {
                    Text("以下记录已在 Watch 确认，但无法自动归位。")
                        .font(.caption)
                        .foregroundStyle(DZColor.ink700)
                        .padding(.horizontal, DZMetric.sectionHeaderPadding)

                    ForEach(unresolvedRecords, id: \.clientSubmissionID) { record in
                        WatchSetSubmissionReviewCard(
                            record: record,
                            reassign: {
                                relocatingClientSubmissionID = record.clientSubmissionID
                            },
                            discard: {
                                pendingDiscardClientSubmissionID = record.clientSubmissionID
                            }
                        )
                    }
                }
            }
            .padding(DZMetric.contentPadding)
        }
        .dzScreenBackground()
        .navigationTitle("需用户处理")
        .sheet(
            isPresented: Binding(
                get: { relocatingClientSubmissionID != nil },
                set: { isPresented in
                    if isPresented == false {
                        relocatingClientSubmissionID = nil
                    }
                }
            )
        ) {
            if let record = record(clientSubmissionID: relocatingClientSubmissionID) {
                WatchSetSubmissionReassignSheet(
                    record: record,
                    errorMessage: $errorMessage
                )
            }
        }
        .confirmationDialog(
            "丢弃这条记录？",
            isPresented: Binding(
                get: { pendingDiscardClientSubmissionID != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDiscardClientSubmissionID = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("丢弃", role: .destructive) {
                discardPendingRecord()
            }
            Button("取消", role: .cancel) {
                pendingDiscardClientSubmissionID = nil
            }
        }
        .alert(
            "处理失败",
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

    private func record(clientSubmissionID: String?) -> WatchSetSubmissionRecord? {
        guard let clientSubmissionID else {
            return nil
        }

        return records.first { $0.clientSubmissionID == clientSubmissionID }
    }

    private func discardPendingRecord() {
        guard let record = record(clientSubmissionID: pendingDiscardClientSubmissionID) else {
            pendingDiscardClientSubmissionID = nil
            return
        }

        do {
            try WatchSetSubmissionReviewService.discard(record: record, in: modelContext)
            PhoneWatchTrainingStateSync.shared.refresh(in: modelContext)
            pendingDiscardClientSubmissionID = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WatchSetSubmissionReviewCard: View {
    let record: WatchSetSubmissionRecord
    let reassign: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sourceText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DZColor.bronze700)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(reasonText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DZColor.skull600)
                        .lineLimit(1)
                }

                Text(record.exerciseName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(DZColor.ink900)

                HStack(spacing: 6) {
                    metric("重量", "\(WeightDisplay.text(record.weight)) \(record.weightUnit.label)")
                    metric("次数", "\(record.reps)")
                    if let rpe = record.rpe {
                        metric("RPE", "\(rpe)")
                    }
                    if let sideText {
                        metric("侧别", sideText)
                    }
                    metric("完成", record.completedAt.formatted(date: .omitted, time: .shortened))
                }
            }
            .padding(14)

            DZDivider()

            HStack(spacing: 0) {
                Button(action: reassign) {
                    Label("归位", systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DZColor.pump500)
                .padding(.vertical, 12)

                DZDivider()

                Button(action: discard) {
                    Label("丢弃", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DZColor.skull600)
                .padding(.vertical, 12)
            }
            .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dzCardStyle()
    }

    private var sourceText: String {
        if record.originalSessionName.isEmpty {
            return "原训练未知"
        }

        return record.originalSessionName
    }

    private var reasonText: String {
        switch record.reason {
        case .sessionNotFound:
            "训练已删除"
        case .exerciseNotFound:
            "动作已变化"
        case .syncTimeout:
            "同步超时"
        case nil:
            "需处理"
        }
    }

    private var sideText: String? {
        switch record.side {
        case .left:
            "左"
        case .right:
            "右"
        case nil:
            nil
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        Text("\(title) \(value)")
            .font(DZFont.mono(size: 12, weight: .semibold))
            .foregroundStyle(DZColor.ink800)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DZColor.cream200)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct WatchSetSubmissionReassignSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let record: WatchSetSubmissionRecord
    @Binding var errorMessage: String?
    @State private var candidates: [WatchSetSubmissionReviewCandidate] = []
    @State private var selectedCandidate: WatchSetSubmissionReviewCandidate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DZMetric.sectionSpacing) {
                    if candidates.isEmpty {
                        DZSection {
                            Text("没有含匹配动作的训练。")
                                .foregroundStyle(DZColor.ink900)
                                .padding(14)
                        }
                    } else {
                        DZSection("选择训练与动作") {
                            VStack(spacing: 0) {
                                ForEach(candidates) { candidate in
                                    Button {
                                        selectedCandidate = candidate
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(candidate.sessionName)
                                                    .foregroundStyle(DZColor.ink900)

                                                Text(candidateSubtitle(candidate))
                                                    .font(.caption)
                                                    .foregroundStyle(DZColor.ink700)
                                            }

                                            Spacer()

                                            if selectedCandidate == candidate {
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

                                    if candidate.id != candidates.last?.id {
                                        DZDivider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(DZMetric.contentPadding)
            }
            .dzScreenBackground()
            .navigationTitle("归位到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        relocate()
                    }
                    .disabled(selectedCandidate == nil)
                }
            }
            .onAppear(perform: loadCandidates)
        }
    }

    private func loadCandidates() {
        do {
            candidates = try WatchSetSubmissionReviewService.candidates(for: record, in: modelContext)
            selectedCandidate = candidates.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func relocate() {
        guard let selectedCandidate else {
            return
        }

        do {
            try WatchSetSubmissionReviewService.relocate(
                record: record,
                toSessionID: selectedCandidate.sessionID,
                exerciseOrderIndex: selectedCandidate.exerciseOrderIndex,
                in: modelContext
            )
            PhoneWatchTrainingStateSync.shared.refresh(in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func candidateSubtitle(_ candidate: WatchSetSubmissionReviewCandidate) -> String {
        let date = candidate.sessionStartedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(date) · \(candidate.exerciseName)"
    }
}
