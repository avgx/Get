import Foundation

public protocol RequestObserver: Sendable {
    func willSend(_ request: URLRequest) async
    func didCompleteSuccess(_ request: URLRequest, response: URLResponse, body: Data, duration: TimeInterval) async
    func didCompleteFailure(_ request: URLRequest, error: Error, duration: TimeInterval) async
    /// JSON (or other) decode of the response body failed after a successful HTTP load.
    func didDecodeFailure(
        _ request: URLRequest,
        response: URLResponse,
        body: Data,
        expectedDecodableTypeName: String,
        error: Error
    ) async
}

public extension RequestObserver {
    func willSend(_ request: URLRequest) async {}
    func didCompleteSuccess(_ request: URLRequest, response: URLResponse, body: Data, duration: TimeInterval) async {}
    func didCompleteFailure(_ request: URLRequest, error: Error, duration: TimeInterval) async {}
    func didDecodeFailure(
        _ request: URLRequest,
        response: URLResponse,
        body: Data,
        expectedDecodableTypeName: String,
        error: Error
    ) async {}
}

public final class NoopRequestObserver: RequestObserver, Sendable {
    public init() {}
}

