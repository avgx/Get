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

public struct FanoutRequestObserver: RequestObserver, Sendable {
    private let observers: [any RequestObserver]
    
    public init(observers: [any RequestObserver]) {
        self.observers = observers
    }
    
    public  func willSend(_ request: URLRequest) async {
        for observer in observers {
            await observer.willSend(request)
        }
    }
    
    public  func didCompleteSuccess(_ request: URLRequest, response: URLResponse, body: Data, duration: TimeInterval) async {
        for observer in observers {
            await observer.didCompleteSuccess(request, response: response, body: body, duration: duration)
        }
    }
    
    public  func didCompleteFailure(_ request: URLRequest, error: Error, duration: TimeInterval) async {
        for observer in observers {
            await observer.didCompleteFailure(request, error: error, duration: duration)
        }
    }
    
    public  func didDecodeFailure(
        _ request: URLRequest,
        response: URLResponse,
        body: Data,
        expectedDecodableTypeName: String,
        error: Error
    ) async {
        for observer in observers {
            await observer.didDecodeFailure(
                request,
                response: response,
                body: body,
                expectedDecodableTypeName: expectedDecodableTypeName,
                error: error
            )
        }
    }
}
