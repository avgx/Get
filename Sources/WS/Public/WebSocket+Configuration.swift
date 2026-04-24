import Foundation
import SSLPinning

extension WebSocket {
    /// `WebSocket` client settings.
    public struct Configuration: Sendable {
        /// TLS certificate chain evaluation (same idea as HTTP session delegate).
        public var serverTrustPolicy: ServerTrustPolicy
        /// Maximum size of a single `URLSessionWebSocketTask` message.
        public var maximumMessageSize: Int
        /// When true, log sent/received byte sizes via ``WebSocket``’s logger (SwiftLog / DebugThings).
        public var logSentReceivedBytes: Bool
        /// Seconds to wait for the WebSocket handshake (`didOpen`).
        public var connectionHandshakeTimeout: TimeInterval
        /// Periodic ping interval in seconds; `nil` disables ping.
        public var pingInterval: TimeInterval?
        /// When set, disconnect if no inbound messages (and no successful pong) for longer than this interval (seconds).
        public var readIdleTimeout: TimeInterval?
        /// Mirrors key `URLSessionConfiguration` timeouts / connectivity for the socket session.
        public var timeoutIntervalForRequest: TimeInterval
        public var timeoutIntervalForResource: TimeInterval
        public var waitsForConnectivity: Bool
        
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
            logSentReceivedBytes: Bool = false,
            connectionHandshakeTimeout: TimeInterval = 30,
            pingInterval: TimeInterval? = nil,
            readIdleTimeout: TimeInterval? = nil,
            timeoutIntervalForRequest: TimeInterval = 60,
            timeoutIntervalForResource: TimeInterval = 604_800,
            waitsForConnectivity: Bool = false,
            serverTrustPolicy: ServerTrustPolicy = .system
        ) {
            self.maximumMessageSize = maximumMessageSize
            self.logSentReceivedBytes = logSentReceivedBytes
            self.connectionHandshakeTimeout = connectionHandshakeTimeout
            self.pingInterval = pingInterval
            self.readIdleTimeout = readIdleTimeout
            self.timeoutIntervalForRequest = timeoutIntervalForRequest
            self.timeoutIntervalForResource = timeoutIntervalForResource
            self.waitsForConnectivity = waitsForConnectivity
            self.serverTrustPolicy = serverTrustPolicy
        }
        
        public static let `default` = Self.init()
        
        public static let checked = Self.init(
            logSentReceivedBytes: true,
            pingInterval: TimeInterval(10),
            readIdleTimeout: TimeInterval(10),
            timeoutIntervalForRequest: TimeInterval(10),
            waitsForConnectivity: true
        )
    }
}
