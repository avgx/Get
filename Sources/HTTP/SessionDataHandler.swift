import Foundation

public protocol SessionDataHandler: Sendable {
    func didReceive(response: URLResponse)
    func didReceive(data: Data)
    func didComplete(error: Error?)
    func evaluateDisposition(for response: URLResponse) -> URLSession.ResponseDisposition
}

public extension SessionDataHandler {
    func evaluateDisposition(for response: URLResponse) -> URLSession.ResponseDisposition {
        .allow
    }
}

//final class StreamAdapter: SessionDataHandler {
//    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
//
//    init(_ continuation: AsyncThrowingStream<Data, Error>.Continuation) {
//        self.continuation = continuation
//    }
//
//    func didReceive(response: URLResponse) {}
//
//    func didReceive(data: Data) {
//        continuation.yield(data)
//    }
//
//    func didComplete(error: Error?) {
//        if URLSessionTaskCancellation.isCancellation(error) {
//            continuation.finish()
//            return
//        }
//        if let error {
//            continuation.finish(throwing: error)
//        } else {
//            continuation.finish()
//        }
//    }
//}
