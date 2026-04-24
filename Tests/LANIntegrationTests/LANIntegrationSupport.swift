import Foundation
import Testing

/// Shared LAN gate (`GET_TEST_LAN`, host, Basic auth) and stream helpers for integration tests.
enum LANIntegration {
    /// Active when `GET_TEST_LAN=1` and `GET_TEST_PASSWORD` is non-empty.
    /// Values from `.env` at package root; process environment overrides (see `TestEnvironment`).
    static var credentials: (host: String, user: String, password: String)? {
        guard TestEnvironment.value(for: "GET_TEST_LAN") == "1" else { return nil }
        let host = TestEnvironment.value(for: "GET_TEST_HOST") ?? "192.168.1.41"
        let user = TestEnvironment.value(for: "GET_TEST_USER") ?? "root"
        let password = TestEnvironment.value(for: "GET_TEST_PASSWORD") ?? ""
        guard !password.isEmpty else { return nil }
        return (host, user, password)
    }

    static func basicAuthorizedGET(path: String) -> URLRequest? {
        guard let (host, user, password) = credentials else { return nil }
        guard path.hasPrefix("/"), let url = URL(string: "http://\(host)\(path)") else { return nil }
        var request = URLRequest(url: url)
        let token = Data("\(user):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// `ws://` + Basic `Authorization` (same credentials as HTTP). Path must start with `/`.
    static func basicAuthorizedWebSocketRequest(path: String) -> URLRequest? {
        guard let (host, user, password) = credentials else { return nil }
        guard path.hasPrefix("/"), let url = URL(string: "ws://\(host)\(path)") else { return nil }
        var request = URLRequest(url: url)
        let token = Data("\(user):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// First element from `stream`, or `nil` if another task finishes first (timeout / empty).
    static func firstValue<T: Sendable>(in stream: AsyncStream<T>, timeoutNanoseconds: UInt64 = 25_000_000_000) async -> T? {
        await withTaskGroup(of: (T?).self) { group in
            group.addTask { () -> T? in
                for await value in stream {
                    return value
                }
                return nil
            }
            group.addTask { () -> T? in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            guard let outer = await group.next() else {
                group.cancelAll()
                return nil
            }
            group.cancelAll()
            return outer
        }
    }

    /// First element from a throwing stream, or `nil` on timeout / empty. Propagates stream errors.
    static func firstValue<T: Sendable>(in stream: AsyncThrowingStream<T, Error>, timeoutNanoseconds: UInt64 = 25_000_000_000) async throws -> T? {
        try await withThrowingTaskGroup(of: (T?).self) { group in
            group.addTask { () async throws -> T? in
                for try await value in stream {
                    return value
                }
                return nil
            }
            group.addTask { () async throws -> T? in
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            guard let outer = try await group.next() else {
                group.cancelAll()
                return nil
            }
            group.cancelAll()
            return outer
        }
    }

    /// Collects at least `minimumCount` elements, or whatever the stream produced before it ended. Races against `timeoutNanoseconds`.
    ///
    /// If the timeout wins first, waits for the collector task so partial results are still returned (useful for LAN diagnostics).
    static func collectAtLeastThrowing<T: Sendable>(
        minimumCount: Int,
        from stream: AsyncThrowingStream<T, Error>,
        timeoutNanoseconds: UInt64 = 25_000_000_000
    ) async throws -> [T] {
        try await withThrowingTaskGroup(of: [T]?.self) { group in
            group.addTask { () async throws -> [T]? in
                var out: [T] = []
                for try await item in stream {
                    out.append(item)
                    if out.count >= minimumCount {
                        return out
                    }
                }
                return out
            }
            group.addTask { () async throws -> [T]? in
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            guard let first = try await group.next() else {
                group.cancelAll()
                return []
            }
            if let arr = first {
                group.cancelAll()
                return arr
            }
            guard let second = try await group.next() else {
                group.cancelAll()
                return []
            }
            group.cancelAll()
            return second ?? []
        }
    }

    /// First WebSocket frame from `stream`, or `nil` on timeout / end without a message.
    static func firstWebSocketMessage(
        in stream: AsyncStream<URLSessionWebSocketTask.Message>,
        timeoutNanoseconds: UInt64 = 25_000_000_000
    ) async -> URLSessionWebSocketTask.Message? {
        await firstValue(in: stream, timeoutNanoseconds: timeoutNanoseconds)
    }
}
