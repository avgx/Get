import Foundation
import DebugThings

final class RecordingURLSessionTaskLogger: URLSessionTaskLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var created = 0
    private var dataChunks = 0
    private var completed = 0
    private var metrics = 0
    private var decoding = 0

    func counts() -> (created: Int, dataChunks: Int, completed: Int, metrics: Int, decoding: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (created, dataChunks, completed, metrics, decoding)
    }

    func logTaskCreated(_ task: URLSessionTask) {
        lock.lock()
        created += 1
        lock.unlock()
    }

    func logTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        completed += 1
        lock.unlock()
    }

    func logTask(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        self.metrics += 1
        lock.unlock()
    }

    func logTask(_ task: URLSessionTask, didFinishDecodingWithError error: Error?) {
        lock.lock()
        decoding += 1
        lock.unlock()
    }

    func logDataTask(_ dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        dataChunks += 1
        lock.unlock()
    }
}
