import DebugThings
import Foundation
import HTTP
import SSLPinning
import Testing
import WS

// MARK: - WebSocket (WS module)

/// Requires `GET_TEST_WS_PATH` (e.g. `/some/ws`). Opens ``WebSocket`` over `ws://` with Basic auth, expects `.connected` and at least one incoming message.
@Test(.tags(.integration))
func lanWebSocketConnectAndFirstMessage() async throws {
    guard let path = TestEnvironment.value(for: "GET_TEST_WS_PATH"), !path.isEmpty else {
        return
    }
    guard let request = LANIntegration.basicAuthorizedWebSocketRequest(path: path) else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    var configuration = WebSocket.Configuration.default
    configuration.serverTrustPolicy = .system
    configuration.connectionHandshakeTimeout = 25
    let socket = WebSocket(request: request, configuration: configuration)
    let stream = await socket.messages()
    await socket.connect()
    let state = await socket.connectionState()
    guard case .connected = state else {
        if case let .disconnected(reason) = state {
            Issue.record("WebSocket did not connect: \(String(describing: reason))")
        } else {
            Issue.record("WebSocket did not reach connected state: \(String(describing: state))")
        }
        await socket.disconnect()
        return
    }
    let message = await LANIntegration.firstWebSocketMessage(in: stream)
    #expect(message != nil, "No WebSocket message within timeout (check GET_TEST_WS_PATH and server).")
    await socket.disconnect()
}

/// Ten minutes of inbound traffic: logs each frame payload size and ``WebSocket/State`` transitions.
/// Enabled only when `GET_TEST_WS_LONG_LISTEN=1` (same LAN / `GET_TEST_WS_PATH` as the short WS test). Scaffold for token rotation and reconnect observation.
@Test(.tags(.integration), .disabled("TODO: WS reconnect after token refresh; disabled for now."))
func lanWebSocketLongListenPayloadBytesAndState() async throws {
    guard TestEnvironment.value(for: "GET_TEST_WS_LONG_LISTEN") == "1" else {
        return
    }
    guard let path = TestEnvironment.value(for: "GET_TEST_WS_PATH"), !path.isEmpty else {
        return
    }
    guard let request = LANIntegration.basicAuthorizedWebSocketRequest(path: path) else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    var configuration = WebSocket.Configuration.default
    configuration.serverTrustPolicy = .system
    configuration.connectionHandshakeTimeout = 25
    let socket = WebSocket(request: request, configuration: configuration)
    let stream = await socket.messages()

    let stateTask = Task {
        let stateStream = await socket.connectionStateUpdates()
        for await state in stateStream {
            print("[WS long listen] state: \(String(describing: state))")
        }
    }
    defer { stateTask.cancel() }

    await socket.connect()
    let state = await socket.connectionState()
    guard case .connected = state else {
        if case let .disconnected(reason) = state {
            Issue.record("WebSocket did not connect: \(String(describing: reason))")
        } else {
            Issue.record("WebSocket did not reach connected state: \(String(describing: state))")
        }
        await socket.disconnect()
        return
    }

    let tenMinutesNanos: UInt64 = 600 * 1_000_000_000
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for await message in stream {
                let bytes = webSocketMessagePayloadByteCount(message)
                print("[WS long listen] message bytes: \(bytes)")
            }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: tenMinutesNanos)
        }
        await group.next()
        group.cancelAll()
    }

    await socket.disconnect()
}

private func webSocketMessagePayloadByteCount(_ message: URLSessionWebSocketTask.Message) -> Int {
    switch message {
    case .string(let s):
        return s.utf8.count
    case .data(let d):
        return d.count
    @unknown default:
        return 0
    }
}
