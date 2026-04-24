import Foundation


/// Ошибки публичного API `WebSocketClient`, не приходящие напрямую от `URLSession`.
public enum WebSocketError: Swift.Error, Sendable, Equatable {
    /// Нет активного сокета (ещё не подключились или уже отключились).
    case notConnected
    /// Некорректная конфигурация (например, отсутствует URL в запросе).
    case invalidConfiguration(String)
    /// Рукопожатие WebSocket не завершилось за `connectionHandshakeTimeout`.
    case handshakeTimeout
    /// Рукопожатие завершилось ошибкой от системы.
    case handshakeFailed(underlyingDescription: String)
}

