import Foundation
import SSLPinning

/// What `URLSession` reports about an opened WebSocket task.
enum TransportEvent: Sendable {
    /// `didCloseWith`: the server sent a close frame.
    case closed(code: Int, reason: Data?)
    /// `didCompleteWithError` after the handshake: the task is over.
    case completed(Error?)
}

/// `URLSession` delegate for one connection attempt: TLS challenge, handshake outcome, then transport events.
///
/// Never touches `WebSocket` state. The handshake outcome goes to ``handshake``; everything after it goes to
/// ``events``. Both are one-shot channels owned by the attempt, so a callback that arrives after the attempt
/// is over lands nowhere.
final class Delegate: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate, @unchecked Sendable {
    let handshake = ResumeOnce<Void>()
    let events: AsyncStream<TransportEvent>

    private let tls: ServerTrustEvaluator
    private let eventsContinuation: AsyncStream<TransportEvent>.Continuation
    private let lock = NSLock()
    private var opened = false

    /// One delegate per `URLSession`, one session per attempt.
    init(serverTrustPolicy: ServerTrustPolicy) {
        self.tls = ServerTrustEvaluator(policy: serverTrustPolicy)
        (events, eventsContinuation) = AsyncStream.makeStream(of: TransportEvent.self)
        super.init()
    }

    /// Ends ``events``; later callbacks are dropped. Call when the attempt is over.
    func finish() {
        eventsContinuation.finish()
    }

    /// System callback: server trust goes through `ServerTrustPolicy`, other challenges get default handling.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.serverTrust != nil
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let result = tls.evaluate(challenge)
        completionHandler(result.disposition, result.credential)
    }

    /// System callback: handshake succeeded.
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol `protocol`: String?) {
        lock.lock()
        opened = true
        lock.unlock()
        handshake.resume(.success(()))
    }

    /// System callback: close frame from the server.
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        eventsContinuation.yield(.closed(code: closeCode.rawValue, reason: reason))
    }

    /// System callback: the task is over. Before `didOpen` this is the handshake failure, after it a link event.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let wasOpened = opened
        lock.unlock()

        guard wasOpened else {
            handshake.resume(.failure(HandshakeFailure(error: error, response: task.response)))
            return
        }
        eventsContinuation.yield(.completed(error))
    }
}

/// Handshake ended without `didOpen`. Carries the HTTP response: a failed upgrade reports its status only there.
struct HandshakeFailure: Error, @unchecked Sendable {
    let error: Error?
    let response: URLResponse?
}
