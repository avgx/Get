import Foundation

/// Connection state hub: holds the current value and broadcasts updates to subscribers;
/// a new subscriber immediately receives the latest state.
actor StateHub {
    private var state: WebSocket.State = .idle
    private var listeners: [UUID: AsyncStream<WebSocket.State>.Continuation] = [:]

    /// Current transport state.
    public func current() -> WebSocket.State {
        state
    }

    func set(_ newState: WebSocket.State) {
        state = newState
        for c in listeners.values {
            c.yield(newState)
        }
    }

    /// Update stream: first element is the state at subscription time, then each subsequent change.
    public func updates() -> AsyncStream<WebSocket.State> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<WebSocket.State>.makeStream()
        continuation.onTermination = { @Sendable _ in
            Task { await self.unregister(id: id) }
        }
        listeners[id] = continuation
        continuation.yield(state)
        return stream
    }

    private func register(id: UUID, continuation: AsyncStream<WebSocket.State>.Continuation) {
        listeners[id] = continuation
    }

    private func unregister(id: UUID) {
        listeners.removeValue(forKey: id)
    }
}
