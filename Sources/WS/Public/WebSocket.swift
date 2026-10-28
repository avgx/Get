import Foundation
import Network
import DebugThings
import HTTP
import Logging

/// A WebSocket that keeps itself connected and reports, at every moment, whether a link exists.
///
/// Usage, one owner per socket:
/// 1. Create it, start one task that iterates ``messages`` and one that iterates ``states``. Both live as long as
///    the socket; the owner forwards content and state to whoever else needs them.
/// 2. `connect()` when the link is wanted, `disconnect(reason:)` when it is not; repeat as often as needed.
///    Reconnects after failures follow ``Configuration/reconnect``.
/// 3. On ``State/connected`` (re)send whatever the server needs (subscriptions, play commands): every connection
///    is a new server session.
/// 4. `shutdown()` when the socket is no longer needed. A socket that is one session (`reconnect` is `.never`, and
///    `connect()` is not called again) can instead call `shutdownWhenLinkEnds()` before `connect()`: the first
///    ``State/disconnected(reason:)`` then ends the streams by itself.
///
/// Internally one supervisor task owns the transport. Each attempt runs entirely inside it, so events of an
/// attempt that is over can never affect the current one, and only the supervisor publishes state.
public actor WebSocket {
    /// Every inbound frame of every connection of this socket, in order.
    ///
    /// One consumer, one iteration for the whole lifetime of the socket: the stream survives reconnects and ends
    /// only on `shutdown()`, on the first ``State/disconnected(reason:)`` after `shutdownWhenLinkEnds()`, or on
    /// deinit. Cancelling the iterating task ends the stream for good (`AsyncStream` semantics), so do not cancel
    /// and restart the reader on reconnects. Frames arriving while nobody iterates are buffered.
    public nonisolated let messages: AsyncStream<URLSessionWebSocketTask.Message>

    /// Every published state, in order, starting with ``State/idle``.
    ///
    /// Same rules as ``messages``: one consumer, one iteration for the whole lifetime of the socket; ends only on
    /// `shutdown()`, on the first ``State/disconnected(reason:)`` after `shutdownWhenLinkEnds()`, or on deinit;
    /// cancelling the iterating task ends it for good. States published while nobody
    /// iterates are buffered and none is dropped, so a reader started late still sees every transition.
    /// Use ``connectionState()`` for a one-off snapshot.
    public nonisolated let states: AsyncStream<State>

    private let request: URLRequest
    private let requestAdapter: any RequestAdapter
    private let configuration: Configuration
    private let logger: Logger
    private let traffic = TrafficCounter()
    private let messagesContinuation: AsyncStream<URLSessionWebSocketTask.Message>.Continuation
    private let statesContinuation: AsyncStream<State>.Continuation

    private var state: State = .idle

    private var supervisor: Task<Void, Never>?
    private var wanted = false
    private var isShutDown = false
    private var stopReason: State.DisconnectReason = .userInitiated
    private var connection: Connection?
    private var awaitingFirstOutcome = false
    private var firstOutcomeWaiters: [CheckedContinuation<Void, Never>] = []
    private var endStreamsWhenDisconnected = false

    /// Creates an idle socket; nothing touches the network until `connect()`.
    ///
    /// `request.url` must be `ws://` or `wss://` (traps otherwise: a programming error). `requestAdapter` runs
    /// before every attempt, so a refreshed token reaches the next handshake. `logger` gets `ws.url` metadata
    /// (host and path); put the channel name into its metadata (e.g. `ws.channel`) before passing it in.
    public init(
        request: URLRequest,
        configuration: Configuration,
        requestAdapter: any RequestAdapter = NoopRequestInterceptor(),
        logger: Logger = Logger(label: "ws")
    ) {
        guard let url = request.url else {
            preconditionFailure("WebSocket: URLRequest.url must not be nil")
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            preconditionFailure("WebSocket: invalid URL")
        }
        let scheme = components.scheme?.lowercased()
        precondition(
            scheme.map { ["ws", "wss"].contains($0) } ?? false,
            "WebSocket: URL scheme must be ws, wss"
        )

        #if targetEnvironment(simulator)
        if #available(iOS 26.0, *) {
            nw_tls_create_options()
        }
        #endif

        var logger = logger
        logger[metadataKey: "ws.url"] = "\(components.host ?? "")\(components.path)"

        self.request = request
        self.configuration = configuration
        self.logger = logger
        self.requestAdapter = requestAdapter
        (messages, messagesContinuation) = AsyncStream.makeStream(of: URLSessionWebSocketTask.Message.self)
        (states, statesContinuation) = AsyncStream.makeStream(of: State.self)
        statesContinuation.yield(.idle)
    }

    deinit {
        messagesContinuation.finish()
        statesContinuation.finish()
    }
}

// MARK: - Public API

extension WebSocket {
    /// Current state. A snapshot: follow changes through ``states``.
    public func connectionState() -> State {
        state
    }

    /// Asks for the link and keeps it up according to ``Configuration/reconnect``.
    ///
    /// Returns at once, after registering the request; attempts run in the background and show up in ``states``.
    /// Use ``firstAttemptOutcome()`` to wait for the result. When the link is already wanted, changes nothing.
    /// No-op after `shutdown()`.
    ///
    /// Calls from independent unstructured `Task`s run in no particular order; serialize them on the caller side
    /// when order matters (e.g. scene phase changes).
    public func connect() {
        guard !isShutDown, !wanted else { return }
        wanted = true
        awaitingFirstOutcome = true
        let previous = supervisor
        supervisor = Task {
            await previous?.value
            await self.runSupervisor()
        }
        logger.info("websocket connect requested")
    }

    /// Waits until the first attempt after the latest `connect()` has an outcome and returns the state then:
    /// ``State/connected``, ``State/reconnecting(attempt:delay:after:)`` or ``State/disconnected(reason:)``.
    ///
    /// Returns the current state at once when no first attempt is pending (never connected, already settled,
    /// stopped). A `disconnect(reason:)` meanwhile also ends the wait. Cancelling the caller does not shorten it.
    public func firstAttemptOutcome() async -> State {
        if awaitingFirstOutcome {
            await withCheckedContinuation { firstOutcomeWaiters.append($0) }
        }
        return state
    }

    /// Drops the link and stops reconnecting until the next `connect()`.
    ///
    /// Returns after the transport is fully torn down; the last published state is then
    /// ``State/disconnected(reason:)`` with `reason`, unless a `connect()` arrived meanwhile (it wins).
    /// Pass `.userInitiated`, `.backgroundSuspended` or `.networkUnavailable`. Safe in any state, any number of times.
    public func disconnect(reason: State.DisconnectReason = .userInitiated) async {
        wanted = false
        stopReason = reason
        guard let task = supervisor else {
            completeStop()
            return
        }
        logger.info("websocket disconnect requested: \(String(describing: reason))")
        task.cancel()
        await task.value
        guard supervisor == task else { return }
        supervisor = nil
        completeStop()
    }

    /// Final stop: `disconnect()`, then ends ``messages`` and ``states`` (the last state is
    /// ``State/disconnected(reason:)`` with `.userInitiated`).
    ///
    /// Call once, when the owner is done with the socket. Later `connect()` calls do nothing.
    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        await disconnect(reason: .userInitiated)
        messagesContinuation.finish()
        statesContinuation.finish()
        logger.info("websocket shut down")
    }

    /// Ends ``messages`` and ``states`` on the first ``State/disconnected(reason:)``, the same way `shutdown()` does.
    ///
    /// For a socket that is one session: ``Configuration/reconnect`` is `.never`, and `connect()` is not called again
    /// after a stop. Call once, before `connect()`. The owner keeps reading ``states`` and still sees why the link
    /// ended; frames already buffered are delivered, then ``messages`` ends, so the reader does not wait forever.
    /// `disconnect(reason:)` ends the streams too, and a later `connect()` does nothing. A disconnect that already
    /// happened ends the streams at once.
    public func shutdownWhenLinkEnds() {
        endStreamsWhenDisconnected = true
        if case .disconnected = state {
            finishStreams()
        }
    }

    /// Bytes sent and received over all connections of this socket.
    public func transportMetrics() -> (bytesSent: UInt64, bytesReceived: UInt64) {
        traffic.snapshot()
    }

    /// Sends a text frame on the current connection.
    ///
    /// Throws ``WebSocketError/notConnected`` outside ``State/connected``, or the transport error if the link drops
    /// meanwhile. Nothing is queued or resent: after a reconnect, resend from the ``State/connected`` handler.
    public func sendString(_ string: String) async throws {
        try await send(.string(string))
    }

    /// Sends a binary frame on the current connection. Same rules as ``sendString(_:)``.
    public func sendBinary(_ data: Data) async throws {
        try await send(.data(data))
    }
}

// MARK: - Supervisor

extension WebSocket {
    /// Attempt / serve / back off loop. Runs only inside the `supervisor` task, one at a time.
    ///
    /// Exits on cancellation (from `disconnect`) without publishing: `disconnect` publishes the final state once the
    /// task is over. Exits by itself on a terminal reason, publishing ``State/disconnected(reason:)``.
    /// Publishes nothing after cancellation: every publication follows a cancellation check with no suspension
    /// in between.
    private func runSupervisor() async {
        var attempt = 1
        var failures = 0
        while !Task.isCancelled {
            publish(.connecting(attempt: attempt))
            logger.info("websocket attempt \(attempt)")
            let outcome = await runAttempt()
            guard !Task.isCancelled else { return }

            if outcome.wasConnected {
                attempt = 1
                failures = 1
            } else {
                attempt += 1
                failures += 1
            }

            let reason = outcome.reason
            guard reason.canReconnect, let delay = configuration.reconnect.delay(afterFailures: failures) else {
                logger.warning("websocket stopped: \(String(describing: reason))")
                wanted = false
                supervisor = nil
                publish(.disconnected(reason: reason))
                resumeFirstOutcomeWaiters()
                return
            }

            logger.warning("websocket link ended: \(String(describing: reason)); attempt \(attempt) in \(delay)s")
            publish(.reconnecting(attempt: attempt, delay: delay, after: reason))
            resumeFirstOutcomeWaiters()
            do {
                try await Task.sleep(nanoseconds: Timing.sleepNanoseconds(delay))
            } catch {
                return
            }
        }
    }

    /// One attempt: adapt the request, open, serve until the link ends. Call only from `runSupervisor`.
    ///
    /// The connection is closed on every exit path. `wasConnected` tells whether ``State/connected`` was published.
    private func runAttempt() async -> (reason: State.DisconnectReason, wasConnected: Bool) {
        let adapted: URLRequest
        do {
            adapted = try await requestAdapter.adapt(request)
        } catch {
            return (.classifyTransportError(error), false)
        }
        guard !Task.isCancelled else { return (.urlSessionError(.cancelled), false) }

        let connection = Connection(request: adapted, configuration: configuration, traffic: traffic)
        defer { connection.close() }

        if let failure = await connection.open() {
            return (failure, false)
        }
        guard !Task.isCancelled else { return (.urlSessionError(.cancelled), false) }

        self.connection = connection
        defer { self.connection = nil }
        publish(.connected)
        logger.info("websocket connected")
        resumeFirstOutcomeWaiters()

        let messagesContinuation = self.messagesContinuation
        let reason = await connection.run { messagesContinuation.yield($0) }
        return (reason, true)
    }

    /// Publishes the final ``State/disconnected(reason:)`` of a stop requested by `disconnect`.
    /// Call only when no supervisor is running.
    private func completeStop() {
        publish(.disconnected(reason: stopReason))
        resumeFirstOutcomeWaiters()
        logger.info("websocket disconnected: \(String(describing: stopReason))")
    }
}

// MARK: - State and helpers

extension WebSocket {
    /// Sets the state and yields it into ``states``. Synchronous, so a transition never interleaves with other calls.
    /// Repeated equal states are not republished. After `shutdownWhenLinkEnds()`, the first
    /// ``State/disconnected(reason:)`` also ends both streams.
    private func publish(_ newState: State) {
        guard newState != state else { return }
        state = newState
        statesContinuation.yield(newState)
        if endStreamsWhenDisconnected, case .disconnected = newState {
            finishStreams()
        }
    }

    /// Ends ``messages`` and ``states`` and refuses later `connect()` calls. No-op after `shutdown()`: that path
    /// finishes the streams itself, after tearing the transport down.
    private func finishStreams() {
        guard !isShutDown else { return }
        isShutDown = true
        messagesContinuation.finish()
        statesContinuation.finish()
        logger.info("websocket shut down")
    }

    /// Releases ``firstAttemptOutcome()`` callers waiting for the first outcome of the current series.
    private func resumeFirstOutcomeWaiters() {
        awaitingFirstOutcome = false
        let waiters = firstOutcomeWaiters
        firstOutcomeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Sends on the current connection if there is one.
    private func send(_ message: URLSessionWebSocketTask.Message) async throws {
        guard case .connected = state, let connection else {
            throw WebSocketError.notConnected
        }
        try await connection.send(message)
    }
}
