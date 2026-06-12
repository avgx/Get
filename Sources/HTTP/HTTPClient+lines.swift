import Foundation

private final class LineThrowingStreamDataHandler: SessionDataHandler, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let buffer = UTF8NewlineLineBuffer()
    private let policy: UTF8InvalidLinePolicy
    private var lastResponse: URLResponse?
    private let onTransportError: @Sendable (Error) -> Void
    private let onCompletedSuccessfully: @Sendable (URLResponse) -> Void

    init(
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        policy: UTF8InvalidLinePolicy,
        onTransportError: @escaping @Sendable (Error) -> Void,
        onCompletedSuccessfully: @escaping @Sendable (URLResponse) -> Void
    ) {
        self.continuation = continuation
        self.policy = policy
        self.onTransportError = onTransportError
        self.onCompletedSuccessfully = onCompletedSuccessfully
    }

    func didReceive(response: URLResponse) {
        lastResponse = response
    }

    func didReceive(data: Data) {
        for line in buffer.append(data, policy: policy) {
            continuation.yield(line)
        }
    }

    func didComplete(error: Error?) {
        if isCancellation(error) {
            if let tail = buffer.drainTailIfAny(policy: policy) {
                continuation.yield(tail)
            }
            continuation.finish()
            return
        }
        if let error {
            onTransportError(error)
            continuation.finish(throwing: error)
            return
        }
        if let tail = buffer.drainTailIfAny(policy: policy) {
            continuation.yield(tail)
        }
        if let response = lastResponse {
            onCompletedSuccessfully(response)
        }
        continuation.finish()
    }
    
    func isCancellation(_ error: Error?) -> Bool {
        guard let error else { return false }
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}

extension HTTPClient {
    /// Incremental UTF-8 text: yields complete lines delimited by `\n` over a TLS-streaming data task.
    /// Transport errors finish the stream by throwing. Retries are not applied here; use the caller or ``HTTPClient/data(for:)`` if you need retrier behaviour.
    public func streamLines(
        request: URLRequest,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) async -> AsyncThrowingStream<String, Error> {
        let trust = serverTrustPolicy
        let redirect = redirectDisposition
        let log = logger
        let intercept = interceptor
        let observe = observer
        let baseConfig = session.configuration
        let startTime = Date()

        return AsyncThrowingStream { continuation in
            let setup = Task {
                var urlRequest = request
                do {
                    urlRequest = try await intercept.adapt(urlRequest)
                    let adaptedRequest = urlRequest
                    await observe.willSend(adaptedRequest)

                    let onTransportError: @Sendable (Error) -> Void = { error in
                        Task {
                            await observe.didCompleteFailure(
                                adaptedRequest,
                                error: error,
                                duration: Date().timeIntervalSince(startTime)
                            )
                        }
                    }
                    let onCompletedSuccessfully: @Sendable (URLResponse) -> Void = { response in
                        Task {
                            await observe.didCompleteSuccess(
                                adaptedRequest,
                                response: response,
                                body: Data(),
                                duration: Date().timeIntervalSince(startTime)
                            )
                        }
                    }

                    let handler = LineThrowingStreamDataHandler(
                        continuation: continuation,
                        policy: .omitInvalidUTF8,
                        onTransportError: onTransportError,
                        onCompletedSuccessfully: onCompletedSuccessfully
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
                    let dataTask = streamSession.dataTask(with: adaptedRequest)
                    continuation.onTermination = { @Sendable _ in
                        dataTask.cancel()
                        streamSession.invalidateAndCancel()
                    }
                    dataTask.resume()
                } catch {
                    if error is CancellationError {
                        continuation.finish(throwing: error)
                        return
                    }
                    await observe.didCompleteFailure(
                        urlRequest,
                        error: error,
                        duration: Date().timeIntervalSince(startTime)
                    )
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                setup.cancel()
            }
        }
    }
}
