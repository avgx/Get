import Foundation

/// Хаб состояния соединения:
/// хранит текущее значение и рассылает его всем подписчикам;
/// новый подписчик сразу получает актуальное состояние.
actor StateHub {
    private var state: WebSocket.State = .idle
    private var listeners: [UUID: AsyncStream<WebSocket.State>.Continuation] = [:]

    /// Текущее состояние транспорта.
    public func current() -> WebSocket.State {
        state
    }

    func set(_ newState: WebSocket.State) {
        state = newState
        for c in listeners.values {
            c.yield(newState)
        }
    }

    /// Поток обновлений: первый элемент — текущее состояние на момент подписки, далее — каждое изменение.
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
