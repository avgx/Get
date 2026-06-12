import Foundation
import EncodeDecode
import HTTP

final class MultipartStreamHandler: SessionDataHandler, @unchecked Sendable {
    private let state = MultipartState()
    private let continuation: AsyncThrowingStream<MultipartFrame, Error>.Continuation
    private let observer: any RequestObserver
    private let notifyRequest: URLRequest

    init(
        continuation: AsyncThrowingStream<MultipartFrame, Error>.Continuation,
        observer: any RequestObserver,
        notifyRequest: URLRequest
    ) {
        self.continuation = continuation
        self.observer = observer
        self.notifyRequest = notifyRequest
    }

    func evaluateDisposition(for response: URLResponse) -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse else { return .cancel }
        // Part headers and disposition are read from the same `HTTPURLResponse` URLSession passes here (before body bytes).
        return state.responseDisposition(http)
    }

    /// Intentionally empty: headers for each part are handled in `evaluateDisposition` via `MultipartSession.responseDisposition`.
    func didReceive(response: URLResponse) {}

    func didReceive(data: Data) {
        do {
            for frame in try state.append(data) {
                continuation.yield(frame)
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func didComplete(error: Error?) {
        if isCancellation(error) {
            do {
                for frame in try state.finish() {
                    continuation.yield(frame)
                }
            } catch {
                continuation.finish(throwing: error)
                return
            }
            continuation.finish()
            return
        }
        if let error {
            Task { await observer.didCompleteFailure(notifyRequest, error: error, duration: 0) }
            continuation.finish(throwing: error)
            return
        }
        do {
            for frame in try state.finish() {
                continuation.yield(frame)
            }
        } catch {
            continuation.finish(throwing: error)
            return
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
