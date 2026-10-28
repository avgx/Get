import Foundation
import HTTP
import WS

/// The single reader of `socket.states`; collects every state.
final class StateRecorder: Sendable {
    private let storage = Storage<WebSocket.State>()
    let task: Task<Void, Never>

    init(_ socket: WebSocket) {
        let storage = self.storage
        let stream = socket.states
        task = Task {
            for await state in stream {
                storage.append(state)
            }
            storage.markEnded()
        }
    }

    var states: [WebSocket.State] { storage.items }
    var isEnded: Bool { storage.isEnded }
}

/// Lock-protected list for recorders.
final class Storage<Item: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Item] = []
    private var ended = false

    var items: [Item] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var isEnded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ended
    }

    func append(_ item: Item) {
        lock.lock()
        recorded.append(item)
        lock.unlock()
    }

    func markEnded() {
        lock.lock()
        ended = true
        lock.unlock()
    }
}

/// Collects text frames from `socket.messages`.
final class MessageRecorder: Sendable {
    private let storage = Storage<String>()
    let task: Task<Void, Never>

    init(_ socket: WebSocket) {
        let storage = self.storage
        let stream = socket.messages
        task = Task {
            for await message in stream {
                if case .string(let text) = message {
                    storage.append(text)
                }
            }
            storage.markEnded()
        }
    }

    var texts: [String] { storage.items }
    var isEnded: Bool { storage.isEnded }
}

/// Puts `Authorization: Bearer token-<n>` on the n-th adapted request.
actor CountingTokenAdapter: RequestAdapter {
    private var count = 0

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        count += 1
        var request = request
        request.setValue("Bearer token-\(count)", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Polls `condition` until it holds or `timeout` elapses; returns whether it held.
func eventually(timeout: TimeInterval = 5, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

extension WebSocket.State {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var reconnectReason: WebSocket.State.DisconnectReason? {
        if case .reconnecting(_, _, let after) = self { return after }
        return nil
    }
}
