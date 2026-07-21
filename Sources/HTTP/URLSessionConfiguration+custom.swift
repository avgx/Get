import Foundation

extension URLSessionConfiguration {
    /// Short timeouts for ordinary REST (`data` / `send`) via account runtime.
    public class var custom: URLSessionConfiguration {
        let x: URLSessionConfiguration = .ephemeral
        x.timeoutIntervalForRequest = 10
        x.timeoutIntervalForResource = 30
        x.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return x
    }

    /// Long-lived multipart / MJPEG streams (`HTTPClient.frames`).
    ///
    /// Idle between parts may exceed REST request timeouts; the whole transfer
    /// must outlive `.custom`'s 30s resource cap. Auth and TLS still come from
    /// the owning ``HTTPClient`` (interceptor + ``serverTrustPolicy``).
    public class var longLivedStreaming: URLSessionConfiguration {
        let x: URLSessionConfiguration = .ephemeral
        x.timeoutIntervalForRequest = 120
        x.timeoutIntervalForResource = 604_800
        x.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return x
    }
}
