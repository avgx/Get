import Foundation

public protocol SessionHandler: Sendable {
    func taskCreated(_ task: URLSessionTask)
    func urlSession(_ session: URLSession, _ task: URLSessionTask, didCompleteWithError error: Error?)
    func urlSession(_ session: URLSession, _ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics)
    func urlSession(_ session: URLSession, _ task: URLSessionTask, didFinishDecodingWithError error: Error?)
    func urlSession(_ session: URLSession, _ dataTask: URLSessionDataTask, didReceive data: Data)
}
