//import Foundation
//import SSLPinning
//import DebugThings
//
//extension SessionDelegate {
//    /// Separate ``URLSession`` for streaming: same TLS, redirects, and task logger; custom ``SessionDataHandler``.
//    public func cloneForStreaming(handler: (any SessionDataHandler)?) -> SessionDelegate {
//        SessionDelegate(
//            serverTrustPolicy: serverTrustPolicy,
//            redirectDisposition: redirectDisposition,
//            handler: handler,
//            logger: logger
//        )
//    }
//}
