import Foundation
import SwiftData

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
protocol PhoneWatchTrainingStateTransport: AnyObject {
    func setIncomingMessageHandler(
        _ handler: @escaping @MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void
    )
    func setDiagnosticHandler(_ handler: @escaping @MainActor (String) -> Void)
    func setActivationSuccessHandler(_ handler: @escaping @MainActor () -> Void)
    func activate()
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
}

@MainActor
final class PhoneWatchTrainingStateSync {
    enum DiagnosticState: Error, Equatable {
        case modelContextUnavailable
        case transportUnavailable
        case activationFailed(String)
        case invalidRequest(String)
        case sourceFailed(String)
        case publishFailed(String)
    }

    static let shared = PhoneWatchTrainingStateSync.live()

    private let transport: PhoneWatchTrainingStateTransport
    private let source: PhoneTrainingStateSource
    private let now: @MainActor () -> Date
    private let makeRequestID: @MainActor () -> String
    private var isActivated = false
    private var modelContext: ModelContext?

    private(set) var latestDiagnostic: DiagnosticState?
    private(set) var latestPublishedMessage: WatchTrainingStateMessage?

    init(
        transport: PhoneWatchTrainingStateTransport,
        source: PhoneTrainingStateSource = .live,
        now: @escaping @MainActor () -> Date = Date.init,
        makeRequestID: @escaping @MainActor () -> String = { UUID().uuidString }
    ) {
        self.transport = transport
        self.source = source
        self.now = now
        self.makeRequestID = makeRequestID
    }

    static func live() -> PhoneWatchTrainingStateSync {
        #if canImport(WatchConnectivity)
        if let transport = WCSessionPhoneTrainingStateTransport() {
            return PhoneWatchTrainingStateSync(transport: transport)
        }
        #endif

        return PhoneWatchTrainingStateSync(
            transport: UnavailablePhoneWatchTrainingStateTransport(),
            source: .live
        )
    }

    func bind(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func activate() {
        guard isActivated == false else { return }

        transport.setIncomingMessageHandler { [weak self] message, reply in
            self?.handleIncomingMessage(message, reply: reply)
        }
        transport.setDiagnosticHandler { [weak self] message in
            self?.latestDiagnostic = .activationFailed(message)
        }
        transport.setActivationSuccessHandler { [weak self] in
            self?.handleActivationSuccess()
        }
        transport.activate()
        isActivated = true
    }

    func refresh(in modelContext: ModelContext? = nil) {
        if let modelContext {
            bind(modelContext: modelContext)
        }

        guard let context = self.modelContext else {
            latestDiagnostic = .modelContextUnavailable
            return
        }

        let isTraining: Bool

        do {
            isTraining = try source.isTraining(context)
        } catch {
            latestDiagnostic = .sourceFailed(error.localizedDescription)
            return
        }

        let message = WatchTrainingStateMessage.update(
            requestID: makeRequestID(),
            sentAt: now().timeIntervalSince1970,
            isTraining: isTraining
        )

        do {
            try transport.updateApplicationContext(message.propertyList)
            latestPublishedMessage = message
            latestDiagnostic = nil
        } catch let diagnostic as DiagnosticState {
            latestDiagnostic = diagnostic
        } catch {
            latestDiagnostic = .publishFailed(error.localizedDescription)
        }
    }

    private func handleIncomingMessage(
        _ propertyList: [String: Any],
        reply: ([String: Any]) -> Void
    ) {
        do {
            let request = try WatchTrainingStateMessage(propertyList: propertyList)

            guard request.kind == .request else {
                latestDiagnostic = .invalidRequest(request.kind.rawValue)
                return
            }

            guard let context = modelContext else {
                latestDiagnostic = .modelContextUnavailable
                return
            }

            let response = WatchTrainingStateMessage.response(
                requestID: request.requestID ?? "",
                sentAt: now().timeIntervalSince1970,
                isTraining: try source.isTraining(context)
            )
            reply(response.propertyList)
            latestDiagnostic = nil
        } catch let error as WatchTrainingStateMessage.ParseError {
            latestDiagnostic = .invalidRequest(String(describing: error))
        } catch {
            latestDiagnostic = .sourceFailed(error.localizedDescription)
        }
    }

    private func handleActivationSuccess() {
        guard modelContext != nil else { return }

        refresh()
    }
}

private final class UnavailablePhoneWatchTrainingStateTransport: PhoneWatchTrainingStateTransport {
    func setIncomingMessageHandler(
        _ handler: @escaping @MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void
    ) {}

    func setDiagnosticHandler(_ handler: @escaping @MainActor (String) -> Void) {}

    func setActivationSuccessHandler(_ handler: @escaping @MainActor () -> Void) {}

    func activate() {}

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        throw PhoneWatchTrainingStateSync.DiagnosticState.transportUnavailable
    }
}

#if canImport(WatchConnectivity)
private final class WCSessionPhoneTrainingStateTransport: NSObject, PhoneWatchTrainingStateTransport, WCSessionDelegate {
    private let session: WCSession
    private var incomingMessageHandler: (@MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void)?
    private var diagnosticHandler: (@MainActor (String) -> Void)?
    private var activationSuccessHandler: (@MainActor () -> Void)?

    init?(session: WCSession = .default) {
        guard WCSession.isSupported() else {
            return nil
        }

        self.session = session
        super.init()
    }

    @MainActor
    func setIncomingMessageHandler(
        _ handler: @escaping @MainActor ([String: Any], @escaping ([String: Any]) -> Void) -> Void
    ) {
        incomingMessageHandler = handler
        session.delegate = self
    }

    @MainActor
    func setDiagnosticHandler(_ handler: @escaping @MainActor (String) -> Void) {
        diagnosticHandler = handler
    }

    @MainActor
    func setActivationSuccessHandler(_ handler: @escaping @MainActor () -> Void) {
        activationSuccessHandler = handler
    }

    @MainActor
    func activate() {
        session.activate()
    }

    @MainActor
    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        try session.updateApplicationContext(applicationContext)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.diagnosticHandler?(error.localizedDescription)
            }
            return
        }

        guard activationState == .activated else { return }

        Task { @MainActor in
            self.activationSuccessHandler?()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            self.incomingMessageHandler?(message, replyHandler)
        }
    }
}
#endif
