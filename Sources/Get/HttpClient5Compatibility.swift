import Foundation
import SSLPinning

extension URLSessionConfiguration {
    public static var custom: URLSessionConfiguration {
        let x: URLSessionConfiguration = .ephemeral
        x.timeoutIntervalForRequest = 10
        x.timeoutIntervalForResource = 30
        x.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return x
    }
}

extension JSONEncoder {
    public static var custom: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.withoutEscapingSlashes, .prettyPrinted]
        return encoder
    }
}

extension JSONDecoder {
    public static var custom: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}

/// TLS policy matching the historical ``HttpClient5`` surface; maps to ``ServerTrustPolicy``.
public enum SSL: Sendable {
    case system
    case trustEveryone
}

extension SSL {
    func asServerTrustPolicy() -> ServerTrustPolicy {
        switch self {
        case .system: .system
        case .trustEveryone: .trustEveryone
        }
    }
}

extension HttpClient5 {
    /// Logging level for the underlying ``HTTPClient`` task logger (SwiftLog); not Pulse-based.
    public enum LoggerConfiguration: String, Sendable, CaseIterable {
        case none
        case sensitive
        case full
    }
}
