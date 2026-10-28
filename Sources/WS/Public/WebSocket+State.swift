//
//  WebSocket+State.swift
//  WebSocket
//
//  Created by Alexey Govorovsky on 05.04.2026.
//

import Foundation

extension WebSocket {
    /// WebSocket transport state for UI and owner logic.
    ///
    /// A link exists only in ``connected``. The order of states published by one socket always follows the order of
    /// `connect()` / `disconnect(reason:)` calls on it: the last published state describes the last command.
    public enum State: Equatable, Sendable {
        /// Created; `connect()` has not been called yet.
        case idle
        /// Attempt `attempt` (1-based within the current series) is opening the socket.
        /// A series starts at `connect()` and again after every successful connection.
        case connecting(attempt: Int)
        /// Socket is up; frames flow into ``WebSocket/messages``.
        case connected
        /// No link; attempt `attempt` starts after `delay` seconds. `after` is why the previous attempt or link ended.
        case reconnecting(attempt: Int, delay: TimeInterval, after: DisconnectReason)
        /// No link and no further attempts until the next `connect()`.
        case disconnected(reason: DisconnectReason)
    }
}

extension WebSocket.State {
    /// Why an attempt or a link ended.
    public enum DisconnectReason: Equatable, Sendable {
        /// Owner called `disconnect()`.
        case userInitiated
        /// Owner stopped the socket for app lifecycle (e.g. background): `disconnect(reason: .backgroundSuspended)`.
        case backgroundSuspended
        /// Owner stopped the socket because the network is gone: `disconnect(reason: .networkUnavailable)`.
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
        /// `URLSession` / `URLError` level failure. A handshake that did not finish in time is `.timedOut`.
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
    ///
    /// Use for errors coming out of `URLSession`. Pass `response` when the task has one: a failed upgrade reports
    /// its HTTP status only there.
    public static func classifyTransportError(_ error: Error, response: URLResponse? = nil) -> WebSocket.State.DisconnectReason {
        if let http = response as? HTTPURLResponse, (400...599).contains(http.statusCode) {
            return classifyHTTPStatus(http.statusCode)
        }

        let ns = error as NSError
        if let found = findHTTPURLResponse(startingFrom: ns), (400...599).contains(found.statusCode) {
            return classifyHTTPStatus(found.statusCode)
        }

        if let urlError = error as? URLError {
            return .urlSessionError(urlError.code)
        }
        if ns.domain == NSURLErrorDomain {
            return .urlSessionError(URLError.Code(rawValue: ns.code))
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
        default: return .httpClientError(statusCode: status)
        }
    }

    /// Whether another attempt can help. `false` for owner-requested stops and for HTTP 401/403/404/4xx:
    /// the socket then publishes ``WebSocket/State/disconnected(reason:)`` regardless of ``WebSocket/ReconnectPolicy``.
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
