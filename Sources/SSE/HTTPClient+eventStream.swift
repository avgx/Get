import Foundation
import HTTP

/// Structured Server-Sent Events over HTTP (same line transport as ``HTTPClient/streamLines``; parses SSE field blocks).
extension HTTPClient {
    /// Parsed ``SSEEvent`` stream (blank line separates events). Uses ``HTTPClient/streamLines(request:sessionConfiguration:)`` under the hood.
    /// Transport or parsing failures finish the stream by throwing.
    public func eventStream(
        request: URLRequest,
        timeout: TimeInterval = 30.0,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) async -> AsyncThrowingStream<SSEEvent, Error> {
        var req = request
        if timeout > 0 {
            req.timeoutInterval = timeout
        }
        let lineStream = await streamLines(request: req, sessionConfiguration: sessionConfiguration)
        return AsyncThrowingStream { continuation in
            let parseTask = Task {
                var parser = SSEEventAccumulator()
                do {
                    for try await line in lineStream {
                        if let ev = parser.push(line) {
                            continuation.yield(ev)
                        }
                    }
                    if let ev = parser.finish() {
                        continuation.yield(ev)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                parseTask.cancel()
            }
        }
    }
}
