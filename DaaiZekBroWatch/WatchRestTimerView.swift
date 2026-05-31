import SwiftUI

struct WatchRestTimerView: View {
    let state: WatchRestTimerState
    let hapticStatusText: String
    let addThirtySeconds: () -> Void
    let skip: () -> Void
    let next: () -> Void

    private var isZeroed: Bool {
        state.remainingSeconds <= 0
    }

    private var progress: Double {
        min(1, max(0, state.progress))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusHeader
                timerRing
                controls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(WatchPalette.oledBlack.ignoresSafeArea())
        .scrollContentBackground(.hidden)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isZeroed ? "已归零" : "休息中")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isZeroed ? WatchPalette.oledBlack : WatchPalette.pump)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isZeroed ? WatchPalette.pump : WatchPalette.pumpBackground)
                .clipShape(Capsule())

            Text(isZeroed ? hapticStatusText : "下一组准备中")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isZeroed ? WatchPalette.secondaryText : WatchPalette.faintText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(WatchPalette.banner, lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    WatchPalette.pump,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(formattedTime(state.remainingSeconds))
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(WatchPalette.primaryText)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Text("休息 \(state.totalSeconds) 秒")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(WatchPalette.faintText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: 148, height: 148)
        .padding(.vertical, 2)
        .accessibilityIdentifier("watch-rest-timer-ring")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: addThirtySeconds) {
                Text("+30")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WatchPalette.oledBlack)
            .background(WatchPalette.pump)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: isZeroed ? next : skip) {
                Text(isZeroed ? "下一组" : "跳过")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WatchPalette.primaryText)
            .background(WatchPalette.banner)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        return String(format: "%02d:%02d", safeSeconds / 60, safeSeconds % 60)
    }
}

