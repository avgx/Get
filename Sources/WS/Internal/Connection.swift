import Foundation

/// Byte counters shared by all attempts of one `WebSocket`. Safe from any thread.
final class TrafficCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    /// Call after a frame was handed to the transport successfully.
    func addSent(_ bytes: Int) {
        lock.lock()
        sent &+= UInt64(bytes)
        lock.unlock()
    }

    /// Call for every inbound frame, before delivering it.
    func addReceived(_ bytes: Int) {
        lock.lock()
        received &+= UInt64(bytes)
        lock.unlock()
    }

    /// Totals so far; the two values are read together.
    func snapshot() -> (bytesSent: UInt64, bytesReceived: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (sent, received)
    }
}

/// One connection attempt: its own `URLSession`, task and delegate. Never reused.
///
/// Lifetime: `open()` once; if it succeeds, `run(onMessage:)` once; `close()` always, when the attempt is over.
/// Everything the attempt starts lives inside those two calls as child tasks, so nothing from this attempt can
/// outlive it and reach the next one.
final class Connection: @unchecked Sendable {
    typealias Message = URLSessionWebSocketTask.Message
    typealias DisconnectReason = WebSocket.State.DisconnectReason

    private let configuration: WebSocket.Configuration
    private let traffic: TrafficCounter
    private let delegate: Delegate
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    private let lock = NSLock()
    private var lastInboundAt = Date()

    /// Builds the session and task; does not touch the network until `open()`.
    init(request: URLRequest, configuration: WebSocket.Configuration, traffic: TrafficCounter) {
        self.configuration = configuration
        self.traffic = traffic
        self.delegate = Delegate(serverTrustPolicy: configuration.serverTrustPolicy)
        self.session = URLSession(
            configuration: configuration.makeSessionConfiguration(),
            delegate: delegate,
            delegateQueue: nil
        )
        self.task = session.webSocketTask(with: request)
        task.maximumMessageSize = configuration.maximumMessageSize
        task.taskDescription = request.url?.absoluteString ?? "websocket"
    }

    /// Starts the task and waits for the handshake, at most `connectionHandshakeTimeout`.
    ///
    /// Returns `nil` when the socket is open, otherwise why it is not. Returns promptly when the calling task is
    /// cancelled (the result is then meaningless). Call once.
    func open() async -> DisconnectReason? {
        let timeout = configuration.connectionHandshakeTimeout
        let task = self.task
        let handshake = delegate.handshake
        return await withTaskGroup(of: DisconnectReason?.self) { group in
            group.addTask {
                do {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            handshake.install(continuation)
                            task.resume()
                        }
                    } onCancel: {
                        handshake.resume(.failure(CancellationError()))
                    }
                    return nil
                } catch let failure as HandshakeFailure {
                    guard let error = failure.error else {
                        return .urlSessionError(.networkConnectionLost)
                    }
                    return .classifyTransportError(error, response: failure.response)
                } catch {
                    return .urlSessionError(.cancelled)
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: Timing.sleepNanoseconds(timeout))
                } catch {
                    return .urlSessionError(.cancelled)
                }
                return .urlSessionError(.timedOut)
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Serves an open socket until the link ends; returns why it ended.
    ///
    /// Delivers every inbound frame to `onMessage` in order, from a background task. Ends on receive failure,
    /// server close, task completion, failed ping or read-idle timeout, whichever comes first, and on cancellation
    /// of the calling task. Call once, only after `open()` returned `nil`.
    func run(onMessage: @escaping @Sendable (Message) -> Void) async -> DisconnectReason {
        let pingInterval = configuration.pingInterval
        let readIdleTimeout = configuration.readIdleTimeout
        touchInbound()
        return await withTaskCancellationHandler {
            await withTaskGroup(of: DisconnectReason?.self) { group in
                group.addTask { await self.receiveLoop(onMessage: onMessage) }
                group.addTask { await self.watchEvents() }
                if let pingInterval {
                    group.addTask { await self.pingLoop(interval: pingInterval) }
                }
                if let readIdleTimeout {
                    group.addTask { await self.readIdleLoop(timeout: readIdleTimeout) }
                }
                var reason: DisconnectReason?
                for await result in group {
                    if let result {
                        reason = result
                        break
                    }
                }
                close()
                group.cancelAll()
                return reason ?? .urlSessionError(.cancelled)
            }
        } onCancel: {
            self.close()
        }
    }

    /// Sends one frame. Throws the transport error, or `CancellationError` if the calling task is cancelled.
    /// Safe to call concurrently with `run`.
    func send(_ message: Message) async throws {
        let task = self.task
        try await awaitCallback { (done: @escaping @Sendable (Result<Void, Error>) -> Void) in
            task.send(message) { error in
                done(error.map { .failure($0) } ?? .success(()))
            }
        }
        traffic.addSent(Self.payloadSize(message))
    }

    /// Tears the attempt down: cancels the task, drops further delegate events, invalidates the session.
    /// Idempotent, safe from any thread.
    func close() {
        task.cancel(with: .goingAway, reason: nil)
        delegate.finish()
        session.invalidateAndCancel()
    }

    // MARK: - Child tasks of `run`. Each returns `nil` when it stopped because of cancellation.

    /// Reads frames one by one; the only reader of the task.
    private func receiveLoop(onMessage: @Sendable (Message) -> Void) async -> DisconnectReason? {
        let task = self.task
        while !Task.isCancelled {
            let message: Message
            do {
                message = try await awaitCallback { (done: @escaping @Sendable (Result<Message, Error>) -> Void) in
                    task.receive { done($0) }
                }
            } catch {
                return endReason(for: error)
            }
            touchInbound()
            traffic.addReceived(Self.payloadSize(message))
            onMessage(message)
        }
        return nil
    }

    /// The only consumer of the delegate's events; ends when `close()` finishes them.
    private func watchEvents() async -> DisconnectReason? {
        for await event in delegate.events {
            switch event {
            case let .closed(code, reason):
                return .serverClosed(code: code, reason: Self.closeReasonText(reason))
            case .completed(let error):
                guard let error else { return .urlSessionError(.networkConnectionLost) }
                return endReason(for: error)
            }
        }
        return nil
    }

    /// Pings every `interval`; a pong counts as inbound traffic for the read-idle watchdog.
    private func pingLoop(interval: TimeInterval) async -> DisconnectReason? {
        let task = self.task
        while true {
            do {
                try await Task.sleep(nanoseconds: Timing.sleepNanoseconds(interval))
            } catch {
                return nil
            }
            do {
                try await awaitCallback { (done: @escaping @Sendable (Result<Void, Error>) -> Void) in
                    task.sendPing { error in
                        done(error.map { .failure($0) } ?? .success(()))
                    }
                }
            } catch {
                return endReason(for: error)
            }
            touchInbound()
        }
    }

    /// Ends the link when nothing came in for `timeout`; sleeps exactly until the next possible deadline.
    private func readIdleLoop(timeout: TimeInterval) async -> DisconnectReason? {
        while true {
            let remaining = timeout - Date().timeIntervalSince(inboundAt())
            if remaining <= 0 {
                return .urlSessionError(.timedOut)
            }
            do {
                try await Task.sleep(nanoseconds: Timing.sleepNanoseconds(remaining))
            } catch {
                return nil
            }
        }
    }

    // MARK: - Helpers

    /// Reason for a failed receive / ping / completion. A close frame already received wins over the socket error
    /// that usually follows it.
    private func endReason(for error: Error) -> DisconnectReason? {
        if Task.isCancelled || error is CancellationError {
            return nil
        }
        if task.closeCode != .invalid {
            return .serverClosed(code: task.closeCode.rawValue, reason: Self.closeReasonText(task.closeReason))
        }
        return .classifyTransportError(error, response: task.response)
    }

    /// Records inbound activity (frame or pong). Any thread.
    private func touchInbound() {
        lock.lock()
        lastInboundAt = Date()
        lock.unlock()
    }

    /// Time of the last inbound activity. Any thread.
    private func inboundAt() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return lastInboundAt
    }

    /// UTF-8 close reason; `nil` when absent or empty, so equal closes compare equal.
    static func closeReasonText(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Payload bytes of a frame, for traffic counters.
    static func payloadSize(_ message: Message) -> Int {
        switch message {
        case .string(let text): return text.utf8.count
        case .data(let data): return data.count
        @unknown default: return 0
        }
    }
}
