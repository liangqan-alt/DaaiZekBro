import SwiftUI

struct WatchRootView: View {
    @ObservedObject var sessionManager: WatchSessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("训练状态")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(sessionManager.trainingStatusText)
                    .font(.title3.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("连接")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(sessionManager.connectionStatus.rawValue)
                    .font(.footnote.monospaced())
            }

            Spacer(minLength: 0)

            Button {
                sessionManager.requestTrainingState()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(sessionManager.connectionStatus != .reachable)
        }
        .padding(.vertical, 8)
        .onAppear {
            sessionManager.activate()
            sessionManager.refreshFromApplicationContext()
            sessionManager.requestTrainingState()
        }
    }
}

#Preview {
    WatchRootView(sessionManager: WatchSessionManager.preview(
        connectionStatus: .reachable,
        isTraining: true
    ))
}
