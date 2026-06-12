import Foundation
import Network
import DebugThings
import HTTP
import Logging

/// Ensures `resume` is invoked once on the continuation: `URLSession` callbacks may fire more than once when the socket closes.
private final class ContinuationResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func invoke(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        body()
    }
}

public actor WebSocket {
    private let request: URLRequest
    private let requestAdapter: any RequestAdapter

    private var description: String {
        request.url?.absoluteString ?? "<unknown>"
    }

    private let configuration: Configuration
    private let logger: Logger
    private let stateHub = StateHub()

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var delegate: Delegate?

    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var readIdleTask: Task<Void, Never>?

    private var messagesContinuation: AsyncStream<URLSessionWebSocketTask.Message>.Continuation?

    private var userWantsConnected = false
    private var lifecyclePaused = false

    private var bytesSent: UInt64 = 0
    private var bytesReceived: UInt64 = 0

    private var transportDisconnectHandled = false
    private var lastReceiveOrPongAt: Date = .init()

    public init(request: URLRequest, configuration: Configuration, requestAdapter: any RequestAdapter = NoopRequestInterceptor(), logger: Logger = Logger(label: "ws")) {
        guard let url = request.url else {
            preconditionFailure("WebSocket: URLRequest.url must not be nil")
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            preconditionFailure("WebSocket: invalid URL")
        }
        let scheme = components.scheme?.lowercased()
        let allowed = Set(["ws", "wss"])
        precondition(
            scheme.map { allowed.contains($0) } ?? false,
            "WebSocket: URL scheme must be ws, wss"
        )
        
        #if targetEnvironment(simulator)
        if #available(iOS 26.0, *) {
            nw_tls_create_options()
        }
        #endif
        
        self.request = request
        self.configuration = configuration
        self.logger = logger
        self.requestAdapter = requestAdapter
    }
}

// MARK: - Public API

extension WebSocket {
    public func connectionState() async -> State {
        await stateHub.current()
    }

    public func connectionStateUpdates() async -> AsyncStream<State> {
        await stateHub.updates()
    }

    /// Single stream of incoming frames. Only one active `messages()` stream at a time; call again after it finishes.
    public func messages() async -> AsyncStream<URLSessionWebSocketTask.Message> {
        precondition(messagesContinuation == nil, "WebSocketClient: only one active messages() stream at a time")
        var captured: AsyncStream<URLSessionWebSocketTask.Message>.Continuation!
        let stream = AsyncStream<URLSessionWebSocketTask.Message> { captured = $0 }
        messagesContinuation = captured
        captured.onTermination = { @Sendable _ in
            Task { await self.onMessagesStreamTerminated() }
        }
        if webSocketTask != nil {
            startReceiveLoopIfNeeded()
        }
        return stream
    }

    public func connect() async {
        logger.info("websocket connect \(description)")
        userWantsConnected = true
        guard !lifecyclePaused else {
            logger.debug("connect ignored: lifecycle paused (background)")
            return
        }

        await stateHub.set(.connecting)
        do {
            try await openSocketAndHandshake()
            transportDisconnectHandled = false
            lastReceiveOrPongAt = Date()
            await stateHub.set(.connected)
            if messagesContinuation != nil {
                startReceiveLoopIfNeeded()
            }
            startPingLoopIfConfigured()
            startReadIdleMonitorIfConfigured()
            logger.info("websocket connected")
        } catch is CancellationError {
            logger.debug("websocket connect cancelled")
            await teardownAfterFailedOpen()
            await stateHub.set(.disconnected(reason: .underlying(URLError(.cancelled))))
        } catch let error as WebSocketError {
            logger.error("websocket connect failed: \(error)")
            await teardownAfterFailedOpen()
            await stateHub.set(.disconnected(reason: mapClientErrorToDisconnect(error)))
        } catch {
            logger.error("websocket connect failed: \(error.localizedDescription)")
            await teardownAfterFailedOpen()
            await stateHub.set(.disconnected(reason: State.DisconnectReason.classifyTransportError(error)))
        }
    }

    public func disconnect() async {
        logger.info("websocket disconnect \(description)")
        userWantsConnected = false
        lifecyclePaused = false
        transportDisconnectHandled = true
        cancelChildTasksAndTeardownTransport()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        invalidateURLSession()
        finishMessagesStreamIfNeeded()
        await stateHub.set(.disconnected(reason: .userInitiated))
        logger.info("websocket disconnected by user")
    }

    public func transportMetrics() -> (bytesSent: UInt64, bytesReceived: UInt64) {
        (bytesSent: bytesSent, bytesReceived: bytesReceived)
    }

    public func sendString(_ string: String) async throws {
        guard let task = webSocketTask else {
            throw WebSocketError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            task.send(.string(string)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        if configuration.logSentReceivedBytes {
            logger.debug("sent string \(string.utf8.count) bytes")
        }
        bytesSent += UInt64(string.utf8.count)
    }

    public func sendBinary(_ data: Data) async throws {
        guard let task = webSocketTask else {
            throw WebSocketError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            task.send(.data(data)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        if configuration.logSentReceivedBytes {
            logger.debug("sent binary \(data.count) bytes")
        }
        bytesSent += UInt64(data.count)
    }
}

// MARK: - Public API for lifecycle manipulators

extension WebSocket {
    public func announceReconnectAttempt(_ attempt: Int) async {
        await stateHub.set(.reconnecting(attempt: attempt))
    }

    public func applicationWillDeactivate() async {
        lifecyclePaused = true
        transportDisconnectHandled = true
        cancelChildTasksAndTeardownTransport()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        invalidateURLSession()
        finishMessagesStreamIfNeeded()
        await stateHub.set(.disconnected(reason: .backgroundSuspended))
        logger.debug("websocket suspended for application deactivate")
    }

    public func applicationDidBecomeActive(shouldReconnect: Bool) async {
        lifecyclePaused = false
        guard shouldReconnect, userWantsConnected else { return }
        let state = await stateHub.current()
        if case .connected = state { return }
        logger.debug("websocket resuming after application activate")
        await connect()
    }

    public func suspendForNetworkUnavailable() async {
        transportDisconnectHandled = true
        cancelChildTasksAndTeardownTransport()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        invalidateURLSession()
        finishMessagesStreamIfNeeded()
        if userWantsConnected {
            await stateHub.set(.disconnected(reason: .networkUnavailable))
        }
        logger.debug("websocket suspended: network unavailable")
    }
}

// MARK: - Messages stream

extension WebSocket {
    private func onMessagesStreamTerminated() async {
        receiveTask?.cancel()
        receiveTask = nil
        messagesContinuation = nil
    }

    private func finishMessagesStreamIfNeeded() {
        messagesContinuation?.finish()
        messagesContinuation = nil
    }
}

// MARK: - Session and transport

extension WebSocket {
    private func openSocketAndHandshake() async throws {
        await teardownAfterFailedOpen()
        transportDisconnectHandled = false

        let delegate = Delegate(serverTrustPolicy: configuration.serverTrustPolicy)
        delegate.onServerClosed = { code, reason in
            Task { await self.handleDelegateServerClosed(code: code, reason: reason) }
        }
        delegate.onTaskFinished = { nsError in
            Task { await self.handleDelegateTaskFinished(nsError: nsError) }
        }

        let sessionConfig = configuration.makeSessionConfiguration()

        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        let adaptedRequest = try await requestAdapter.adapt(request)
        let task = session.webSocketTask(with: adaptedRequest)
        task.maximumMessageSize = configuration.maximumMessageSize
        task.taskDescription = adaptedRequest.url?.absoluteString ?? "websocket"

        self.urlSession = session
        self.delegate = delegate
        self.webSocketTask = task

        let handshakeNanos = Timing.handshakeTimeoutNanoseconds(configuration.connectionHandshakeTimeout)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        delegate.setHandshakeContinuation(cont)
                        task.resume()
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: handshakeNanos)
                    task.cancel(with: .abnormalClosure, reason: nil)
                    throw WebSocketError.handshakeTimeout
                }
                do {
                    try await group.next()!
                    group.cancelAll()
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } catch {
            await teardownAfterFailedOpen()
            throw error
        }
    }

    private func teardownAfterFailedOpen() async {
        cancelChildTasksAndTeardownTransport()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        invalidateURLSession()
    }

    private func cancelChildTasksAndTeardownTransport() {
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        readIdleTask?.cancel()
        readIdleTask = nil
        delegate?.clearCallbacks()
    }

    private func invalidateURLSession() {
        urlSession?.finishTasksAndInvalidate()
        urlSession = nil
        delegate = nil
    }

    private func mapClientErrorToDisconnect(_ error: WebSocketError) -> State.DisconnectReason {
        switch error {
        case .notConnected:
            return .underlying(URLError(.notConnectedToInternet))
        case .invalidConfiguration(let message):
            // TODO: replace with a typed / clearer disconnect mapping than a generic NSError.
            return .underlying(NSError(domain: "WebSocketClient", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        case .handshakeTimeout:
            return .urlSessionError(.timedOut)
        case .handshakeFailed(let description):
            // TODO: replace with a typed / clearer disconnect mapping than a generic NSError.
            return .underlying(NSError(domain: "WebSocketClient", code: 2, userInfo: [NSLocalizedDescriptionKey: description]))
        }
    }

    private func handleDelegateServerClosed(code: Int, reason: Data?) async {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        await processTransportDisconnectOnce(reason: .serverClosed(code: code, reason: reasonString))
    }

    private func handleDelegateTaskFinished(nsError: NSError?) async {
        if let nsError {
            await processTransportDisconnectOnce(reason: State.DisconnectReason.classifyTransportError(nsError))
        } else {
            await processTransportDisconnectOnce(reason: .underlying(URLError(.networkConnectionLost)))
        }
    }

    private func processTransportDisconnectOnce(reason: State.DisconnectReason) async {
        guard !transportDisconnectHandled else { return }
        transportDisconnectHandled = true

        cancelChildTasksAndTeardownTransport()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        invalidateURLSession()
        finishMessagesStreamIfNeeded()

        if !userWantsConnected {
            await stateHub.set(.disconnected(reason: .userInitiated))
            return
        }

        if lifecyclePaused {
            await stateHub.set(.disconnected(reason: .backgroundSuspended))
            return
        }

        await stateHub.set(.disconnected(reason: reason))
        logger.warning("websocket disconnected: \(String(describing: reason))")
    }
}

// MARK: - Receive, ping, read idle

extension WebSocket {
    private func startReceiveLoopIfNeeded() {
        guard receiveTask == nil else { return }
        guard let task = webSocketTask else { return }
        receiveTask = Task { await self.runReceiveLoop(on: task) }
    }

    private func runReceiveLoop(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>) in
                    let once = ContinuationResumeOnce()
                    task.receive { result in
                        once.invoke { continuation.resume(with: result) }
                    }
                }
            } catch {
                await handleReceiveEnded(error)
                return
            }

            lastReceiveOrPongAt = Date()
            switch message {
            case .string(let text):
                if configuration.logSentReceivedBytes {
                    logger.debug("received string \(text.count) bytes")
                }
                bytesReceived += UInt64(text.utf8.count)
            case .data(let data):
                if configuration.logSentReceivedBytes {
                    logger.debug("received data \(data.count) bytes")
                }
                bytesReceived += UInt64(data.count)
            @unknown default:
                break
            }
            messagesContinuation?.yield(message)
        }
    }

    private func handleReceiveEnded(_ error: Error) async {
        await processTransportDisconnectOnce(reason: State.DisconnectReason.classifyTransportError(error))
    }

    private func startPingLoopIfConfigured() {
        pingTask?.cancel()
        guard let interval = configuration.pingInterval, let task = webSocketTask else { return }
        let nanos = Timing.timeIntervalToSleepNanoseconds(interval)
        pingTask = Task { await self.runPingLoop(sleepNanoseconds: nanos, task: task) }
    }

    private func runPingLoop(sleepNanoseconds: UInt64, task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: sleepNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let current = self.webSocketTask, current === task else { return }
            let pingError = await withCheckedContinuation { (cont: CheckedContinuation<Error?, Never>) in
                let once = ContinuationResumeOnce()
                current.sendPing { err in
                    once.invoke { cont.resume(returning: err) }
                }
            }
            if let pingError {
                await handleReceiveEnded(pingError)
                return
            }
            lastReceiveOrPongAt = Date()
        }
    }

    private func startReadIdleMonitorIfConfigured() {
        readIdleTask?.cancel()
        guard let timeout = configuration.readIdleTimeout else { return }
        let nanos = Timing.timeIntervalToSleepNanoseconds(timeout)
        readIdleTask = Task { await self.runReadIdleMonitor(timeoutSeconds: timeout, sleepNanoseconds: nanos) }
    }

    private func runReadIdleMonitor(timeoutSeconds: TimeInterval, sleepNanoseconds: UInt64) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: sleepNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard self.webSocketTask != nil else { return }
            let elapsed = Date().timeIntervalSince(lastReceiveOrPongAt)
            if elapsed >= timeoutSeconds {
                await handleReceiveEnded(URLError(.timedOut))
                return
            }
        }
    }
}
