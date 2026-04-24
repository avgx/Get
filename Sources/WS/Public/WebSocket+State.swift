//
//  WebSocket+State.swift
//  WebSocket
//
//  Created by Alexey Govorovsky on 05.04.2026.
//

import Foundation

extension WebSocket {
    /// Состояние транспорта WebSocket для отображения в UI и логики переподключения.
    public enum State: Equatable, Sendable {
        /// Клиент создан, активного соединения ещё не было.
        case idle
        /// Устанавливается соединение (включая повтор после обрыва).
        case connecting
        /// Сокет поднят, идёт приём сообщений.
        case connected
        /// Ожидание перед следующей попыткой переподключения (см. `ReconnectPolicy`).
        case reconnecting(attempt: Int)
        /// Соединение закрыто; причина уточняется в `DisconnectReason`.
        case disconnected(reason: DisconnectReason)
    }
}

extension WebSocket.State {
    /// Причина перехода в состояние «отключено».
    public enum DisconnectReason: Equatable, Sendable {
        /// Пользователь вызвал `disconnect()`.
        case userInitiated
        /// Сокет закрыт из‑за политики жизненного цикла (например, уход в фон).
        case backgroundSuspended
        /// Сеть стала недоступной (инициатор — владелец, обычно по `AppLifecycleManager`).
        case networkUnavailable
        /// HTTP 401 при установке соединения / апгрейде.
        case httpUnauthorized
        /// HTTP 403.
        case httpForbidden
        /// HTTP 404.
        case httpNotFound
        /// HTTP 5xx.
        case httpServerError(statusCode: Int)
        /// Другой код 4xx (кроме 401/403/404), если удалось извлечь из ответа.
        case httpClientError(statusCode: Int)
        /// Ошибка уровня `URLSession` / `URLError`.
        case urlSessionError(URLError.Code)
        /// Сервер закрыл соединение по WebSocket (код закрытия и опциональная причина UTF‑8).
        case serverClosed(code: Int, reason: String?)
        /// Прочая или не классифицированная ошибка.
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
    /// Преобразует системную ошибку в более конкретную причину отключения (HTTP-коды апгрейда, `URLError`, и т.д.).
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

    /// Уровень `WebSocket.Session`: переподключать после этого отключения (транспорт/сервер).
    /// Lifecycle и `NWPathMonitor` — причины вроде `.backgroundSuspended` / `.networkUnavailable` (`false`).
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
