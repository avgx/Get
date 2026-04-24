import Foundation
import SSLPinning
import DebugThings

private extension RedirectDisposition {
    /// Handler suitable for ``SessionDelegate``’s `onWillPerformHTTPRedirection`.
    func willPerformHTTPRedirection() -> @Sendable (HTTPURLResponse, URLRequest) async -> URLRequest? {
        switch self {
        case .follow:
            return { _, newRequest in newRequest }
        case .doNotFollow:
            return { _, _ in nil }
        }
    }
}

public final class SessionDelegate: NSObject, URLSessionDelegate, URLSessionDataDelegate {

    private let tls: ServerTrustEvaluator
    private let redirect: @Sendable (HTTPURLResponse, URLRequest) async -> URLRequest?
    private let handler: (any SessionDataHandler)?
    private let logger: any URLSessionTaskLogger

    public let serverTrustPolicy: ServerTrustPolicy
    public let redirectDisposition: RedirectDisposition

    public var certificateChainsByHost: [String: [CertificateInfo]] {
        tls.certificateChainsByHost
    }

    public init(
        serverTrustPolicy: ServerTrustPolicy = .system,
        redirectDisposition: RedirectDisposition = .follow,
        handler: (any SessionDataHandler)? = nil,
        logger: any URLSessionTaskLogger = SimpleURLSessionTaskLogger()
    ) {
        self.serverTrustPolicy = serverTrustPolicy
        self.redirectDisposition = redirectDisposition
        self.tls = ServerTrustEvaluator(policy: serverTrustPolicy)
        self.redirect = redirectDisposition.willPerformHTTPRedirection()
        self.handler = handler
        self.logger = logger
    }

    // TLS
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let result = tls.evaluate(challenge)
        return (result.disposition, result.credential)
    }

    // Redirect
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        await redirect(response, request)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        let disposition = handler?.evaluateDisposition(for: response) ?? .allow
        handler?.didReceive(response: response)
        return disposition
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        logger.logDataTask(dataTask, didReceive: data)
        handler?.didReceive(data: data)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        logger.logTask(task, didCompleteWithError: error)
        handler?.didComplete(error: error)
    }

    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        logger.logTaskCreated(task)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        logger.logTask(task, didFinishCollecting: metrics)
    }
}
