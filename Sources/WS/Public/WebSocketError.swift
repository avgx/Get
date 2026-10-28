import Foundation

/// Errors thrown by the public `WebSocket` API.
public enum WebSocketError: Swift.Error, Sendable, Equatable {
    /// The socket is not in ``WebSocket/State/connected``: nothing was sent.
    case notConnected
}
