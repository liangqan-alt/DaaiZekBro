import Combine
import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, ObservableObject {
    enum ConnectionStatus: String {
        case reachable
        case unreachable
        case inactive
        case unsupported
        case failed
    }

    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var isTraining: Bool?

    private let session: WCSession?

    override init() {
        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
            connectionStatus = session.activationState == .activated
                ? (session.isReachable ? .reachable : .unreachable)
                : .inactive
        } else {
            session = nil
            connectionStatus = .unsupported
        }

        super.init()
    }

    init(session: WCSession?, connectionStatus: ConnectionStatus, isTraining: Bool?) {
        self.session = session
        self.connectionStatus = connectionStatus
        self.isTraining = isTraining
        super.init()
    }

    var trainingStatusText: String {
        guard let isTraining else {
            return "等待 iPhone 状态"
        }

        return isTraining ? "训练中" : "空闲"
    }

    func activate() {
        guard let session else {
            updateConnectionStatus(.unsupported)
            return
        }

        session.delegate = self
        session.activate()
        updateReachability(for: session)
    }

    func refreshFromApplicationContext() {
        guard let session else {
            updateConnectionStatus(.unsupported)
            return
        }

        applyMessage(session.receivedApplicationContext)
        updateReachability(for: session)
    }

    func requestTrainingState() {
        guard let session else {
            updateConnectionStatus(.unsupported)
            return
        }

        updateReachability(for: session)

        guard session.activationState == .activated, session.isReachable else {
            return
        }

        let request = WatchTrainingStateMessage.request(
            requestID: UUID().uuidString,
            sentAt: Date().timeIntervalSince1970
        )

        session.sendMessage(
            request.propertyList,
            replyHandler: { [weak self] reply in
                self?.applyMessage(reply)
            },
            errorHandler: { [weak self] _ in
                self?.updateConnectionStatus(.failed)
            }
        )
    }

    private func applyMessage(_ message: [String: Any]) {
        guard let trainingState = try? WatchTrainingStateMessage(propertyList: message),
              trainingState.kind == .response || trainingState.kind == .update,
              let isTraining = trainingState.isTraining else {
            return
        }

        Task { @MainActor [weak self] in
            self?.isTraining = isTraining
        }
    }

    private func updateReachability(
        for session: WCSession,
        didUpdate: ((ConnectionStatus, ConnectionStatus) -> Void)? = nil
    ) {
        let nextStatus = connectionStatus(for: session)
        updateConnectionStatus(nextStatus, didUpdate: didUpdate)
    }

    private func connectionStatus(for session: WCSession) -> ConnectionStatus {
        switch session.activationState {
        case .activated:
            return session.isReachable ? .reachable : .unreachable
        case .inactive, .notActivated:
            return .inactive
        @unknown default:
            return .failed
        }
    }

    private func updateConnectionStatus(
        _ status: ConnectionStatus,
        didUpdate: ((ConnectionStatus, ConnectionStatus) -> Void)? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let previousStatus = self.connectionStatus
            self.connectionStatus = status
            didUpdate?(previousStatus, status)
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if error != nil {
            updateConnectionStatus(.failed)
            return
        }

        updateReachability(for: session)
        applyMessage(session.receivedApplicationContext)
        requestTrainingState()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateReachability(for: session) { [weak self] previousStatus, nextStatus in
            guard previousStatus == .unreachable, nextStatus == .reachable else {
                return
            }

            self?.requestTrainingState()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyMessage(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        applyMessage(message)
        replyHandler([:])
    }
}

extension WatchSessionManager {
    static func preview(
        connectionStatus: ConnectionStatus,
        isTraining: Bool?
    ) -> WatchSessionManager {
        WatchSessionManager(session: nil, connectionStatus: connectionStatus, isTraining: isTraining)
    }
}
