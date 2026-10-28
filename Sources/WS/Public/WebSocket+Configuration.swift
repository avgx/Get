import Foundation
import SSLPinning

extension WebSocket {
    /// `WebSocket` client settings.
    ///
    /// Build one per socket before calling ``WebSocket/init(request:configuration:requestAdapter:logger:)``;
    /// the socket copies it and never re-reads it.
    public struct Configuration: Sendable {
        /// TLS certificate chain evaluation (same idea as HTTP session delegate).
        public var serverTrustPolicy: ServerTrustPolicy
        /// Maximum size of a single `URLSessionWebSocketTask` message.
        public var maximumMessageSize: Int
        /// Seconds to wait for the WebSocket handshake (`didOpen`). An expired handshake counts as a failed attempt.
        public var connectionHandshakeTimeout: TimeInterval
        /// Periodic ping interval in seconds; `nil` disables ping. A failed ping ends the connection.
        public var pingInterval: TimeInterval?
        /// When set, the connection ends if no inbound frame and no pong arrive for longer than this interval (seconds).
        public var readIdleTimeout: TimeInterval?
        /// What to do after a failed attempt or a dropped connection. See ``ReconnectPolicy``.
        public var reconnect: ReconnectPolicy
        /// Mirrors key `URLSessionConfiguration` timeouts / connectivity for the socket session.
        public var timeoutIntervalForRequest: TimeInterval
        public var timeoutIntervalForResource: TimeInterval
        public var waitsForConnectivity: Bool

        /// Session configuration for one connection attempt. Each attempt gets a fresh `URLSession`.
        public func makeSessionConfiguration() -> URLSessionConfiguration {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeoutIntervalForRequest
            config.timeoutIntervalForResource = timeoutIntervalForResource
            config.waitsForConnectivity = waitsForConnectivity
            config.shouldUseExtendedBackgroundIdleMode = true
            config.networkServiceType = .callSignaling
            #if os(iOS) || os(visionOS)
            // https://developer.apple.com/documentation/foundation/urlsessionconfiguration/improving_network_reliability_using_multipath_tcp
            config.multipathServiceType = .handover
            #endif
            return config
        }

        /// Creates a client configuration.
        public init(
            maximumMessageSize: Int = 16_777_216,
            connectionHandshakeTimeout: TimeInterval = 30,
            pingInterval: TimeInterval? = nil,
            readIdleTimeout: TimeInterval? = nil,
            reconnect: ReconnectPolicy = .never,
            timeoutIntervalForRequest: TimeInterval = 60,
            timeoutIntervalForResource: TimeInterval = 604_800,
            waitsForConnectivity: Bool = false,
            serverTrustPolicy: ServerTrustPolicy = .system
        ) {
            self.maximumMessageSize = maximumMessageSize
            self.connectionHandshakeTimeout = connectionHandshakeTimeout
            self.pingInterval = pingInterval
            self.readIdleTimeout = readIdleTimeout
            self.reconnect = reconnect
            self.timeoutIntervalForRequest = timeoutIntervalForRequest
            self.timeoutIntervalForResource = timeoutIntervalForResource
            self.waitsForConnectivity = waitsForConnectivity
            self.serverTrustPolicy = serverTrustPolicy
        }

        /// One attempt, no ping, no idle watchdog. Suits one-shot sockets such as a single media playback.
        public static let `default` = Self.init()

        /// Short ping and idle watchdog: a dead link is noticed within ~10 s.
        public static let checked = Self.init(
            pingInterval: TimeInterval(10),
            readIdleTimeout: TimeInterval(10),
            timeoutIntervalForRequest: TimeInterval(10),
            waitsForConnectivity: true
        )
    }

    /// Reconnect behaviour after a failed attempt or a dropped connection.
    ///
    /// Reasons with ``State/DisconnectReason/canReconnect`` == `false` (HTTP 401/403/404/4xx) always stop the socket,
    /// whatever the policy says.
    public enum ReconnectPolicy: Sendable, Equatable {
        /// Stop after the first failure or drop: the socket publishes ``State/disconnected(reason:)``.
        case never
        /// Retry forever. The pause before retry `n` (counted from `connect()` or from the last successful connection)
        /// is `min(maxDelay, initial * multiplier^(n - 1))`.
        case exponential(initial: TimeInterval = 1, multiplier: Double = 1.5, maxDelay: TimeInterval = 30)

        /// Pause before the next attempt after `failures` consecutive failures (`failures >= 1`); `nil` means stop.
        func delay(afterFailures failures: Int) -> TimeInterval? {
            switch self {
            case .never:
                return nil
            case let .exponential(initial, multiplier, maxDelay):
                let exponent = Double(max(failures, 1) - 1)
                return min(maxDelay, initial * pow(multiplier, exponent))
            }
        }
    }
}
