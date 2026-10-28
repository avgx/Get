import Foundation
import HTTP
import Testing
import WS

/// Lifecycle contract of `WebSocket` against a local server: state order, reconnects, one lifetime message stream.
@Suite(.timeLimit(.minutes(1)))
struct WebSocketLifecycleTests {
    private static let fastRetry = WebSocket.ReconnectPolicy.exponential(initial: 0.05, multiplier: 1, maxDelay: 0.05)

    private func makeSocket(
        port: UInt16,
        handshakeTimeout: TimeInterval = 2,
        reconnect: WebSocket.ReconnectPolicy = fastRetry,
        adapter: any RequestAdapter = NoopRequestInterceptor()
    ) -> WebSocket {
        var configuration = WebSocket.Configuration.default
        configuration.connectionHandshakeTimeout = handshakeTimeout
        configuration.reconnect = reconnect
        let request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        return WebSocket(request: request, configuration: configuration, requestAdapter: adapter)
    }

    private func closedPort() async throws -> UInt16 {
        let server = try LocalServer(mode: .silent)
        let port = try await server.start()
        server.stop()
        try await Task.sleep(nanoseconds: 50_000_000)
        return port
    }

    @Test func closedPortRetriesAndDisconnectIsFinal() async throws {
        let socket = makeSocket(port: try await closedPort())
        let recorder = StateRecorder(socket)

        await socket.connect()
        #expect(await socket.firstAttemptOutcome().reconnectReason != nil)
        #expect(await eventually { recorder.states.contains(.connecting(attempt: 2)) })

        await socket.disconnect()
        #expect(await socket.connectionState() == .disconnected(reason: .userInitiated))
        #expect(await eventually { recorder.states.last == .disconnected(reason: .userInitiated) })
        let countAfterDisconnect = recorder.states.count
        try await Task.sleep(nanoseconds: 300_000_000)

        let states = recorder.states
        #expect(states.count == countAfterDisconnect, "nothing is published after disconnect returned")
        #expect(states.last == .disconnected(reason: .userInitiated))
        #expect(Array(states.prefix(2)) == [.idle, .connecting(attempt: 1)])
        if states.count > 2, case let .reconnecting(attempt, _, _) = states[2] {
            #expect(attempt == 2)
        } else {
            Issue.record("third state must be .reconnecting, got \(states)")
        }
    }

    @Test func silentServerTimesOutAndKeepsMessagesOpen() async throws {
        let server = try LocalServer(mode: .silent)
        let socket = makeSocket(port: try await server.start(), handshakeTimeout: 0.3)
        let messages = MessageRecorder(socket)

        let started = Date()
        await socket.connect()
        #expect(Date().timeIntervalSince(started) < 0.2, "connect() does not wait for the handshake")
        #expect(await socket.firstAttemptOutcome().reconnectReason == .urlSessionError(.timedOut))
        #expect(await eventually { server.requestHeads.count >= 2 }, "retries after the timeout")
        #expect(!messages.isEnded)

        await socket.disconnect()
        #expect(!messages.isEnded, "disconnect does not end messages")
        await socket.shutdown()
        server.stop()
    }

    @Test func disconnectEndsPendingOutcomeWait() async throws {
        let server = try LocalServer(mode: .silent)
        let socket = makeSocket(port: try await server.start(), handshakeTimeout: 30)

        await socket.connect()
        let waiter = Task { await socket.firstAttemptOutcome() }
        try await Task.sleep(nanoseconds: 100_000_000)
        await socket.disconnect(reason: .backgroundSuspended)
        #expect(await waiter.value == .disconnected(reason: .backgroundSuspended))
        server.stop()
    }

    @Test func notFoundIsTerminal() async throws {
        let server = try LocalServer(mode: .httpStatus(404))
        let socket = makeSocket(port: try await server.start())

        await socket.connect()
        #expect(await socket.firstAttemptOutcome() == .disconnected(reason: .httpNotFound))
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(server.requestHeads.count == 1, "no retries after a terminal reason")
        server.stop()
    }

    @Test func serverCloseReconnectsIntoSameMessagesStream() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: 0.2))
        let socket = makeSocket(port: try await server.start())
        let recorder = StateRecorder(socket)
        let messages = MessageRecorder(socket)

        await socket.connect()
        #expect(await socket.firstAttemptOutcome() == .connected)
        #expect(await eventually { messages.texts.count >= 2 })
        #expect(Array(messages.texts.prefix(2)) == ["hello 1", "hello 2"])

        let reasons = recorder.states.compactMap(\.reconnectReason)
        #expect(reasons.first == .serverClosed(code: 1001, reason: nil))
        #expect(recorder.states.filter(\.isConnected).count >= 2)

        await socket.shutdown()
        server.stop()
    }

    @Test func lastCommandWins() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: nil))
        let socket = makeSocket(port: try await server.start())
        let recorder = StateRecorder(socket)

        for _ in 0..<5 {
            await socket.connect()
            await socket.disconnect()
        }
        await socket.connect()
        #expect(await socket.firstAttemptOutcome() == .connected)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(recorder.states.last == .connected)

        await socket.disconnect(reason: .backgroundSuspended)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(recorder.states.last == .disconnected(reason: .backgroundSuspended))
        #expect(await socket.connectionState() == .disconnected(reason: .backgroundSuspended))

        await socket.shutdown()
        server.stop()
    }

    @Test func connectRacingDisconnectEndsInOneConsistentState() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: nil))
        let socket = makeSocket(port: try await server.start())
        let recorder = StateRecorder(socket)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        await socket.connect()
                    } else {
                        await socket.disconnect()
                    }
                }
            }
        }
        await socket.connect()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(await socket.connectionState() == .connected)
        #expect(recorder.states.last == .connected)

        await socket.shutdown()
        server.stop()
    }

    @Test func shutdownWhenLinkEndsFinishesStreamsWhenServerCloses() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: 0.2))
        let socket = makeSocket(port: try await server.start(), reconnect: .never)
        let recorder = StateRecorder(socket)
        let messages = MessageRecorder(socket)

        await socket.shutdownWhenLinkEnds()
        await socket.connect()
        #expect(await socket.firstAttemptOutcome() == .connected)
        #expect(await eventually { messages.isEnded && recorder.isEnded })
        #expect(messages.texts == ["hello 1"])
        #expect(recorder.states.last == .disconnected(reason: .serverClosed(code: 1001, reason: nil)))

        await socket.connect()
        #expect(
            await socket.connectionState() == .disconnected(reason: .serverClosed(code: 1001, reason: nil)),
            "connect after the link ended does nothing"
        )
        server.stop()
    }

    @Test func shutdownWhenLinkEndsAlsoEndsOnOwnerDisconnect() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: nil))
        let socket = makeSocket(port: try await server.start(), reconnect: .never)
        let recorder = StateRecorder(socket)
        let messages = MessageRecorder(socket)

        await socket.shutdownWhenLinkEnds()
        await socket.connect()
        #expect(await eventually { messages.texts == ["hello 1"] })

        await socket.disconnect()
        #expect(await eventually { messages.isEnded && recorder.isEnded })
        #expect(recorder.states.last == .disconnected(reason: .userInitiated))
        server.stop()
    }

    @Test func serverCloseWithoutShutdownWhenLinkEndsLeavesMessagesOpen() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: 0.2))
        let socket = makeSocket(port: try await server.start(), reconnect: .never)
        let messages = MessageRecorder(socket)

        await socket.connect()
        let closed = WebSocket.State.disconnected(reason: .serverClosed(code: 1001, reason: nil))
        #expect(await eventually { await socket.connectionState() == closed })
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(messages.texts == ["hello 1"])
        #expect(!messages.isEnded, "messages stay open until shutdown()")

        await socket.shutdown()
        #expect(await eventually { messages.isEnded })
        server.stop()
    }

    @Test func shutdownEndsMessagesAndStateStreams() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: nil))
        let socket = makeSocket(port: try await server.start())
        let recorder = StateRecorder(socket)
        let messages = MessageRecorder(socket)

        await socket.connect()
        #expect(await eventually { messages.texts == ["hello 1"] })

        await socket.shutdown()
        #expect(await eventually { messages.isEnded && recorder.isEnded })
        #expect(recorder.states.last == .disconnected(reason: .userInitiated))

        await socket.connect()
        #expect(await socket.connectionState() == .disconnected(reason: .userInitiated), "connect after shutdown does nothing")
        server.stop()
    }

    @Test func lateStatesReaderSeesEveryTransition() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: nil))
        let socket = makeSocket(port: try await server.start())

        await socket.connect()
        _ = await socket.firstAttemptOutcome()
        await socket.disconnect()
        let recorder = StateRecorder(socket)
        #expect(await eventually { recorder.states.count >= 4 })
        #expect(recorder.states == [.idle, .connecting(attempt: 1), .connected, .disconnected(reason: .userInitiated)])

        await socket.shutdown()
        server.stop()
    }

    @Test func adapterRunsBeforeEveryAttempt() async throws {
        let server = try LocalServer(mode: .webSocket(closeAfter: 0.2))
        let socket = makeSocket(port: try await server.start(), adapter: CountingTokenAdapter())

        await socket.connect()
        #expect(await eventually { server.requestHeads.count >= 2 })

        let tokens = server.requestHeads.prefix(2).map { LocalServer.header("Authorization", in: $0) }
        #expect(tokens == ["Bearer token-1", "Bearer token-2"])

        await socket.shutdown()
        server.stop()
    }
}
