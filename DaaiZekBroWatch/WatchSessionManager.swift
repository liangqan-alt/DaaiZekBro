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

    enum DisplayState: Equatable {
        case waitingToStart
        case waitingForTrainingData
        case unreachableNoSnapshot
        case training(snapshot: WatchWorkoutSnapshot, isOffline: Bool)
    }

    private enum SnapshotSource {
        case live
        case cached
    }

    @Published private(set) var connectionStatus: ConnectionStatus
    @Published private(set) var isTraining: Bool?
    @Published private(set) var snapshot: WatchWorkoutSnapshot?

    private let session: WCSession?
    private let userDefaults: UserDefaults
    private var snapshotSource: SnapshotSource?
    private static let cachedSnapshotKey = "WatchSessionManager.cachedSnapshot"

    override init() {
        let userDefaults = UserDefaults.standard
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

        self.userDefaults = userDefaults
        let cachedSnapshot = Self.cachedSnapshot(in: userDefaults)
        snapshot = cachedSnapshot
        snapshotSource = cachedSnapshot == nil ? nil : .cached
        isTraining = cachedSnapshot == nil ? nil : true
        super.init()
    }

    init(
        session: WCSession?,
        connectionStatus: ConnectionStatus,
        isTraining: Bool?,
        snapshot: WatchWorkoutSnapshot? = nil,
        isCachedSnapshot: Bool = false,
        userDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.connectionStatus = connectionStatus
        self.isTraining = isTraining
        self.snapshot = snapshot
        self.userDefaults = userDefaults
        snapshotSource = snapshot == nil ? nil : (isCachedSnapshot ? .cached : .live)
        super.init()
    }

    var trainingStatusText: String {
        guard let isTraining else {
            return "等待 iPhone 状态"
        }

        return isTraining ? "训练中" : "空闲"
    }

    var displayState: DisplayState {
        if let snapshot, snapshotSource == .live {
            return .training(snapshot: snapshot, isOffline: connectionStatus != .reachable)
        }

        switch connectionStatus {
        case .reachable:
            return isTraining == true ? .waitingForTrainingData : .waitingToStart
        case .inactive:
            return isTraining == true ? .waitingForTrainingData : .waitingToStart
        case .unreachable, .failed, .unsupported:
            if let snapshot, snapshotSource == .cached {
                return .training(snapshot: snapshot, isOffline: true)
            }

            return .unreachableNoSnapshot
        }
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
            self?.apply(trainingState: trainingState, isTraining: isTraining)
        }
    }

    @MainActor
    private func apply(trainingState: WatchTrainingStateMessage, isTraining: Bool) {
        self.isTraining = isTraining

        if let snapshot = trainingState.snapshot {
            snapshotSource = .live
            self.snapshot = snapshot
            cache(snapshot)
        } else if isTraining == false {
            snapshotSource = nil
            self.snapshot = nil
            clearCachedSnapshot()
        } else {
            snapshotSource = nil
            self.snapshot = nil
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
            self.restoreCachedSnapshotIfNeeded(for: status)
            didUpdate?(previousStatus, status)
        }
    }

    @MainActor
    private func restoreCachedSnapshotIfNeeded(for status: ConnectionStatus) {
        guard snapshot == nil, isTraining != false else {
            return
        }

        switch status {
        case .unreachable, .failed, .unsupported:
            guard let cachedSnapshot = Self.cachedSnapshot(in: userDefaults) else {
                return
            }

            snapshot = cachedSnapshot
            snapshotSource = .cached
            isTraining = isTraining ?? true
        case .reachable, .inactive:
            break
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
        isTraining: Bool?,
        snapshot: WatchWorkoutSnapshot? = nil,
        isCachedSnapshot: Bool = false
    ) -> WatchSessionManager {
        WatchSessionManager(
            session: nil,
            connectionStatus: connectionStatus,
            isTraining: isTraining,
            snapshot: snapshot,
            isCachedSnapshot: isCachedSnapshot
        )
    }

    private static func cachedSnapshot(in userDefaults: UserDefaults) -> WatchWorkoutSnapshot? {
        guard let propertyList = userDefaults.dictionary(forKey: cachedSnapshotKey) else {
            return nil
        }

        return try? WatchWorkoutSnapshot(propertyList: propertyList)
    }

    private func cache(_ snapshot: WatchWorkoutSnapshot) {
        userDefaults.set(snapshot.propertyList, forKey: Self.cachedSnapshotKey)
    }

    private func clearCachedSnapshot() {
        userDefaults.removeObject(forKey: Self.cachedSnapshotKey)
    }
}
