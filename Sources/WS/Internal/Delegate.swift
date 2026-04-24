import Foundation
import SSLPinning

/// Делегат `URLSession` для WebSocket: рукопожатие, challenge, закрытие сервером и завершение задачи.
/// Не держит ссылку на `WebSocketClient`; колбэки снимаются через `clearCallbacks()` при teardown.
final class Delegate: NSObject, URLSessionWebSocketDelegate, URLSessionDelegate, @unchecked Sendable {

    private let tls: ServerTrustEvaluator

    private let handshakeLock = NSLock()
    private var handshakeContinuation: CheckedContinuation<Void, Error>?
    private var handshakeDidSucceed = false

    var onServerClosed: ((Int, Data?) -> Void)?
    var onTaskFinished: ((NSError?) -> Void)?

    init(serverTrustPolicy: ServerTrustPolicy = .system) {
        self.tls = ServerTrustEvaluator(policy: serverTrustPolicy)
        super.init()
    }

    func setHandshakeContinuation(_ continuation: CheckedContinuation<Void, Error>?) {
        handshakeLock.lock()
        defer { handshakeLock.unlock() }
        handshakeContinuation = continuation
    }

    func clearCallbacks() {
        handshakeLock.lock()
        defer { handshakeLock.unlock() }
        onServerClosed = nil
        onTaskFinished = nil
    }

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

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol `protocol`: String?) {
        handshakeLock.lock()
        handshakeDidSucceed = true
        handshakeLock.unlock()
        _ = `protocol`
        completeHandshake(.success(()))
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onServerClosed?(closeCode.rawValue, reason)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        handshakeLock.lock()
        let opened = handshakeDidSucceed
        handshakeLock.unlock()

        if !opened {
            if let error {
                completeHandshake(.failure(error))
            } else {
                completeHandshake(.failure(URLError(.networkConnectionLost)))
            }
            return
        }

        onTaskFinished?(error.map { $0 as NSError })
    }

    private func completeHandshake(_ result: Result<Void, Error>) {
        handshakeLock.lock()
        let cont = handshakeContinuation
        handshakeContinuation = nil
        handshakeLock.unlock()
        guard let cont else { return }
        switch result {
        case .success:
            cont.resume()
        case .failure(let error):
            cont.resume(throwing: error)
        }
    }
}
