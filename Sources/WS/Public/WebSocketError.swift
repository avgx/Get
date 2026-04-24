import Foundation


/// Errors from the public `WebSocket` API that are not thrown directly as raw `URLSession` errors.
public enum WebSocketError: Swift.Error, Sendable, Equatable {
    /// No active socket (not connected yet or already disconnected).
    case notConnected
    /// Invalid client configuration (e.g. missing URL on the request).
    case invalidConfiguration(String)
    /// Handshake did not complete within `connectionHandshakeTimeout`.
    case handshakeTimeout
    /// Handshake failed with a system-provided description.
    case handshakeFailed(underlyingDescription: String)
}

