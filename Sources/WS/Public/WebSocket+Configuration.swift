import Foundation
import SSLPinning

extension WebSocket {
    /// Настройки `WebSocket`
    public struct Configuration: Sendable {
        /// Политика проверки цепочки сертификата (как у HTTP ``Delegate``).
        public var serverTrustPolicy: ServerTrustPolicy
        /// Максимальный размер одного сообщения на уровне `URLSessionWebSocketTask`.
        public var maximumMessageSize: Int
        /// Логировать размер каждого отправленного и принятого сообщения через ``WebSocket/logger`` (SwiftLog / DebugThings).
        public var logSentReceivedBytes: Bool
        /// Таймаут ожидания `didOpen` рукопожатия WebSocket (секунды).
        public var connectionHandshakeTimeout: TimeInterval
        /// Периодические ping (`nil` — не отправлять), интервал в секундах.
        public var pingInterval: TimeInterval?
        /// Если задано, разрыв при отсутствии входящих сообщений (и успешных ping) дольше интервала (секунды).
        public var readIdleTimeout: TimeInterval?
        /// Параметры `URLSessionConfiguration` для сокета.
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
        
        /// Создаёт конфигурацию клиента.
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
