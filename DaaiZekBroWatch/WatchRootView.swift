import SwiftUI

struct WatchRootView: View {
    @ObservedObject var sessionManager: WatchSessionManager

    var body: some View {
        WatchTrainingSurface(displayState: sessionManager.displayState) {
            sessionManager.requestTrainingState()
        }
        .onAppear {
            sessionManager.activate()
            sessionManager.refreshFromApplicationContext()
            sessionManager.requestTrainingState()
        }
    }
}

private struct WatchTrainingSurface: View {
    let displayState: WatchSessionManager.DisplayState
    let refresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch displayState {
                case .waitingToStart:
                    WatchWaitingStateView(
                        symbol: "figure.strengthtraining.traditional",
                        title: "等待开始",
                        message: "在 iPhone 上开始训练后即可在此查看",
                        showsRefresh: false,
                        refresh: refresh
                    )
                case .waitingForTrainingData:
                    WatchWaitingStateView(
                        symbol: "iphone.gen2.radiowaves.left.and.right",
                        title: "等待训练数据",
                        message: "已检测到训练，正在接收动作列表",
                        showsRefresh: true,
                        refresh: refresh
                    )
                case .unreachableNoSnapshot:
                    WatchWaitingStateView(
                        symbol: "wifi.slash",
                        title: "等待开始",
                        message: "与 iPhone 暂不可达，且无本地训练数据",
                        showsRefresh: true,
                        refresh: refresh
                    )
                case .training(let snapshot, let isOffline):
                    WatchTrainingListView(snapshot: snapshot, isOffline: isOffline)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(WatchPalette.oledBlack.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .tint(WatchPalette.pump)
    }
}

private struct WatchTrainingListView: View {
    let snapshot: WatchWorkoutSnapshot
    let isOffline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchHeaderView(title: snapshot.sessionName, isOffline: isOffline)

            if isOffline {
                WatchOfflineBanner()
            }

            VStack(spacing: 6) {
                ForEach(snapshot.exercises, id: \.exerciseOrderIndex) { exercise in
                    WatchExerciseRow(exercise: exercise)
                }
            }
        }
    }
}

private struct WatchHeaderView: View {
    let title: String
    let isOffline: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(WatchPalette.primaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(isOffline ? WatchPalette.unreachable : WatchPalette.sync)
                    .frame(width: 6, height: 6)

                Text(isOffline ? "离线" : "已连接")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchPalette.secondaryText)
            }
        }
    }
}

private struct WatchOfflineBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("离线")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(WatchPalette.offline)
                .background(WatchPalette.offlineBackground)
                .clipShape(Capsule())

            Text("手机不可达 · 正显示本地快照")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(WatchPalette.secondaryText)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchPalette.banner)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WatchExerciseRow: View {
    let exercise: WatchWorkoutSnapshot.Exercise

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchPalette.primaryText)
                    .lineLimit(2)

                Text(metadataText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WatchPalette.faintText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(exercise.completedSetCount)")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(exercise.completedSetCount > 0 ? WatchPalette.caramel : WatchPalette.faintText)

                Text("组")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchPalette.faintText)
            }
            .accessibilityLabel("\(exercise.completedSetCount) 组")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchPalette.row)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WatchPalette.rowStroke, lineWidth: 1)
        }
    }

    private var metadataText: String {
        let sideText = exercise.isUnilateral ? "单侧" : "双侧"

        return "\(sideText) · \(exercise.defaultRestSeconds) 秒 · \(exercise.weightUnit)"
    }
}

private struct WatchWaitingStateView: View {
    let symbol: String
    let title: String
    let message: String
    let showsRefresh: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WatchPalette.pump)
                .frame(width: 38, height: 38)
                .background(WatchPalette.pumpBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(WatchPalette.primaryText)

                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WatchPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsRefresh {
                Button(action: refresh) {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchPalette.pump)
                .foregroundStyle(WatchPalette.oledBlack)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WatchPalette.row)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum WatchPalette {
    static let oledBlack = Color(red: 0.0, green: 0.0, blue: 0.0)
    static let row = Color(red: 0.141, green: 0.114, blue: 0.082)
    static let banner = Color.white.opacity(0.08)
    static let rowStroke = Color(red: 0.961, green: 0.878, blue: 0.769).opacity(0.10)
    static let primaryText = Color(red: 0.984, green: 0.961, blue: 0.914)
    static let secondaryText = Color(red: 0.984, green: 0.961, blue: 0.914).opacity(0.58)
    static let faintText = Color(red: 0.984, green: 0.961, blue: 0.914).opacity(0.34)
    static let pump = Color(red: 0.941, green: 0.478, blue: 0.235)
    static let pumpBackground = pump.opacity(0.18)
    static let caramel = Color(red: 0.851, green: 0.651, blue: 0.431)
    static let sync = Color(red: 0.510, green: 0.761, blue: 0.353)
    static let unreachable = Color(red: 0.549, green: 0.514, blue: 0.471)
    static let offline = Color(red: 0.718, green: 0.675, blue: 0.612)
    static let offlineBackground = Color(red: 0.984, green: 0.961, blue: 0.914).opacity(0.08)
}

#Preview("等待开始") {
    WatchRootView(sessionManager: WatchSessionManager.preview(
        connectionStatus: .reachable,
        isTraining: false
    ))
}

#Preview("等待训练数据") {
    WatchRootView(sessionManager: WatchSessionManager.preview(
        connectionStatus: .reachable,
        isTraining: true
    ))
}

#Preview("训练列表") {
    WatchRootView(sessionManager: WatchSessionManager.preview(
        connectionStatus: .reachable,
        isTraining: true,
        snapshot: .preview
    ))
}

#Preview("离线快照") {
    WatchRootView(sessionManager: WatchSessionManager.preview(
        connectionStatus: .unreachable,
        isTraining: true,
        snapshot: .preview
    ))
}

private extension WatchWorkoutSnapshot {
    static let preview = WatchWorkoutSnapshot(
        sessionID: UUID().uuidString,
        sessionName: "Push A",
        startedAt: 1_800_000_000,
        exercises: [
            WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: 0,
                name: "坐姿夹胸",
                completedSetCount: 3,
                weightUnit: "kg",
                isUnilateral: false,
                defaultRestSeconds: 90
            ),
            WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: 1,
                name: "侧平举",
                completedSetCount: 1,
                weightUnit: "kg",
                isUnilateral: true,
                defaultRestSeconds: 60
            ),
            WatchWorkoutSnapshot.Exercise(
                exerciseOrderIndex: 2,
                name: "绳索下压",
                completedSetCount: 0,
                weightUnit: "kg",
                isUnilateral: false,
                defaultRestSeconds: 60
            ),
        ]
    )
}
