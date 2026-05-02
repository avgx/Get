import Foundation
import EncodeDecode
import HTTP


extension HTTPClient {
    /// **URLSession per-part** style: first `didReceive` is the outer `multipart/x-mixed-replace` response; later ones carry each part and body bytes until `Content-Length` (or one JPEG without length).
    ///
    /// Retries are not applied here; use ``HTTPClient/data(for:)`` / higher-level orchestration if you need retrier behaviour.
    public func frames(
        request: URLRequest,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) async -> AsyncThrowingStream<MultipartFrame, Error> {
        let trust = serverTrustPolicy
        let redirect = redirectDisposition
        let log = logger
        let intercept = interceptor
        let observe = observer
        let baseConfig = session.configuration

        return AsyncThrowingStream { continuation in
            let setup = Task {
                var urlRequest = request
                do {
                    urlRequest = try await intercept.adapt(urlRequest)
                    await observe.willSend(urlRequest)

                    let handler = MultipartStreamHandler(
                        continuation: continuation,
                        observer: observe,
                        notifyRequest: urlRequest
                    )
                    let delegate = SessionDelegate(
                        serverTrustPolicy: trust,
                        redirectDisposition: redirect,
                        handler: handler,
                        logger: log
                    )
                    let cfg: URLSessionConfiguration = {
                        if let sessionConfiguration { return sessionConfiguration }
                        let c = URLSessionConfiguration.ephemeral
                        c.timeoutIntervalForRequest = baseConfig.timeoutIntervalForRequest
                        c.timeoutIntervalForResource = baseConfig.timeoutIntervalForResource
                        return c
                    }()
                    let streamSession = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
                    let dataTask = streamSession.dataTask(with: urlRequest)
                    continuation.onTermination = { @Sendable _ in
                        dataTask.cancel()
                        streamSession.invalidateAndCancel()
                    }
                    dataTask.resume()
                } catch {
                    await observe.didCompleteFailure(urlRequest, error: error, duration: 0)
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                setup.cancel()
            }
        }
    }
}



