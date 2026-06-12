//import Foundation
//
///// Shared check for user/task cancellation (do not treat as a transport failure).
//public enum URLSessionTaskCancellation {
//    public static func isCancellation(_ error: Error?) -> Bool {
//        guard let error else { return false }
//        if error is CancellationError { return true }
//        let ns = error as NSError
//        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
//    }
//}
