import Foundation

extension URLSessionConfiguration {
    public class var custom: URLSessionConfiguration {
        let x: URLSessionConfiguration = .ephemeral
        x.timeoutIntervalForRequest = 10
        x.timeoutIntervalForResource = 30
        x.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return x
    }
}
