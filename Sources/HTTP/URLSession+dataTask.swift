import Foundation
import RequestResponse

extension URLSession {
    /// Loads a URL request asynchronously while approximating ``URLSessionDataDelegate`` callbacks for the session delegate.
    ///
    /// **Why this exists:** `URLSession` does not reliably invoke ``URLSessionDataDelegate`` when you use Swift-concurrency
    /// `data(for:delegate:)` / `data(from:delegate:)` or completion-handler–based convenience APIs on a session that has a
    /// delegate (see [Pulse #113](https://github.com/kean/Pulse/issues/113) and the community workaround in
    /// [this comment](https://github.com/kean/Pulse/issues/113#issuecomment-1764747469)).
    ///
    /// **What it does:** Runs `dataTask(with:completionHandler:)` and, after completion, **synthetically** calls
    /// `urlSession(_:dataTask:didReceive:)` with the **full** body and `urlSession(_:task:didCompleteWithError:)` on the
    /// session’s delegate when it conforms to ``URLSessionDataDelegate``. That is not true incremental streaming; it only
    /// keeps loggers and proxy delegates consistent with the handler-based task path. If there is no such delegate, the
    /// returned `(Data, URLResponse)` is still valid; only the synthetic forward is skipped.
    public func dataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        final class DataTaskBox: @unchecked Sendable {
            var task: URLSessionDataTask?
        }
        let box = DataTaskBox()

        let onSuccess: @Sendable (Data, URLResponse) -> Void = { [weak self] data, response in
            guard let self, let dataTask = box.task, let dataDelegate = self.delegate as? URLSessionDataDelegate else {
                return
            }
            dataDelegate.urlSession?(self, dataTask: dataTask, didReceive: data)
            dataDelegate.urlSession?(self, task: dataTask, didCompleteWithError: nil)
        }
        let onError: @Sendable (Error) -> Void = { [weak self] error in
            guard let self, let dataTask = box.task, let dataDelegate = self.delegate as? URLSessionDataDelegate else {
                return
            }
            dataDelegate.urlSession?(self, task: dataTask, didCompleteWithError: error)
        }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let task = self.dataTask(with: request) { data, response, error in
                    if let error = error as NSError? {
                        onError(error)
                        return continuation.resume(throwing: error)
                    }

                    guard let data, let response else {
                        let error = error ?? URLError(.badServerResponse)
                        onError(error)
                        return continuation.resume(throwing: error)
                    }
                    onSuccess(data, response)
                    continuation.resume(returning: (data, response))
                }
                box.task = task
                task.resume()
            }
        }, onCancel: {
            box.task?.cancel()
        })
    }
}


