//
//  WebSocket+State.swift
//  WebSocket
//
//  Created by Alexey Govorovsky on 05.04.2026.
//

import Foundation

extension WebSocket {
    /// WebSocket transport state for UI and reconnect logic.
    public enum State: Equatable, Sendable {
        /// Client created; no active connection yet.
        case idle
        /// Connecting or reconnecting after a drop.
        case connecting
        /// Socket is up; receiving messages.
        case connected
        /// Waiting before the next reconnect attempt (see `ReconnectPolicy`).
        case reconnecting(attempt: Int)
        /// Disconnected; see `DisconnectReason`.
        case disconnected(reason: DisconnectReason)
    }
}

extension WebSocket.State {
    /// Why the socket moved to a disconnected state.
    public enum DisconnectReason: Equatable, Sendable {
        /// User called `disconnect()`.
        case userInitiated
        /// Closed due to app lifecycle policy (e.g. background).
        case backgroundSuspended
        /// Network unavailable (owner-driven, often via `AppLifecycleManager`).
        case networkUnavailable
        /// HTTP 401 on connect / upgrade.
        case httpUnauthorized
        /// HTTP 403.
        case httpForbidden
        /// HTTP 404.
        case httpNotFound
        /// HTTP 5xx.
        case httpServerError(statusCode: Int)
        /// Other 4xx (except 401/403/404) when derivable from the response.
        case httpClientError(statusCode: Int)
        /// `URLSession` / `URLError` level failure.
        case urlSessionError(URLError.Code)
        /// Server closed the WebSocket (close code and optional UTF-8 reason).
        case serverClosed(code: Int, reason: String?)
        /// Other or unclassified error.
        case underlying(Error)
        
        public static func == (lhs: DisconnectReason, rhs: DisconnectReason) -> Bool {
            switch (lhs, rhs) {
            case (.userInitiated, .userInitiated),
                (.backgroundSuspended, .backgroundSuspended),
                (.networkUnavailable, .networkUnavailable),
                (.httpUnauthorized, .httpUnauthorized),
                (.httpForbidden, .httpForbidden),
                (.httpNotFound, .httpNotFound):
                return true
            case (.httpServerError(let a), .httpServerError(let b)):
                return a == b
            case (.httpClientError(let a), .httpClientError(let b)):
                return a == b
            case (.urlSessionError(let a), .urlSessionError(let b)):
                return a == b
            case (.serverClosed(let ac, let ar), .serverClosed(let bc, let br)):
                return ac == bc && ar == br
            case (.underlying(let a), .underlying(let b)):
                let na = a as NSError
                let nb = b as NSError
                return na.domain == nb.domain && na.code == nb.code
            default:
                return false
            }
        }
    }
}

extension WebSocket.State.DisconnectReason {
    /// Maps a system error to a more specific disconnect reason (HTTP upgrade status, `URLError`, etc.).
    public static func classifyTransportError(_ error: Error) -> WebSocket.State.DisconnectReason {
        if let urlError = error as? URLError {
            return .urlSessionError(urlError.code)
        }

        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            if let response = findHTTPURLResponse(startingFrom: ns) {
                return classifyHTTPStatus(response.statusCode)
            }
            let code = URLError.Code(rawValue: ns.code)
            return .urlSessionError(code)
        }

        if let response = findHTTPURLResponse(startingFrom: ns) {
            return classifyHTTPStatus(response.statusCode)
        }

        return .underlying(error)
    }

    private static func findHTTPURLResponse(startingFrom error: NSError) -> HTTPURLResponse? {
        var seen = Set<ObjectIdentifier>()
        var current: NSError? = error
        while let e = current {
            let oid = ObjectIdentifier(e)
            guard !seen.contains(oid) else { break }
            seen.insert(oid)
            for (_, value) in e.userInfo {
                if let r = value as? HTTPURLResponse {
                    return r
                }
            }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }

    private static func classifyHTTPStatus(_ status: Int) -> WebSocket.State.DisconnectReason {
        switch status {
        case 401: return .httpUnauthorized
        case 403: return .httpForbidden
        case 404: return .httpNotFound
        case 500...599: return .httpServerError(statusCode: status)
        case 400...499: return .httpClientError(statusCode: status)
        default:
            return .underlying(URLError(.badServerResponse))
        }
    }

    /// Session-level hint: whether to reconnect after this disconnect (transport/server issues).
    /// Lifecycle / `NWPathMonitor` reasons such as `.backgroundSuspended` / `.networkUnavailable` return `false`.
    public var canReconnect: Bool {
        switch self {
        case .userInitiated, .backgroundSuspended, .networkUnavailable:
            return false
        case .httpUnauthorized, .httpForbidden, .httpNotFound, .httpClientError:
            return false
        case .httpServerError, .serverClosed:
            return true
        case .urlSessionError(let code):
            return code != .cancelled
        case .underlying:
            return true
        }
    }
}
