//
//  URLSession+Extension.swift
//  
//
//  Created by Alexey Govorovsky on 04.03.2024.
//  https://github.com/kean/Pulse/issues/113#issuecomment-1764747469

import Foundation

extension URLSession {
    /// Allows to track `URLSessionDataDelegate` using closure based call.
    /// By default if you use async interface or `completionHandler` based interface,
    /// URLSession won't notify `URLSessionDataDelegate`.
    public func dataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        var dataTask: URLSessionDataTask?

        let onSuccess: (Data, URLResponse) -> Void = { (data, response) in
            guard let dataTask, let dataDelegate = self.delegate as? URLSessionDataDelegate else {
                return
            }
            dataDelegate.urlSession?(self, dataTask: dataTask, didReceive: data)
            dataDelegate.urlSession?(self, task: dataTask, didCompleteWithError: nil)
        }
        let onError: (Error) -> Void = { error in
            guard let dataTask, let dataDelegate = self.delegate as? URLSessionDataDelegate else {
                return
            }
            dataDelegate.urlSession?(self, task: dataTask, didCompleteWithError: error)

        }
        let onCancel = {
            dataTask?.cancel()
        }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                dataTask = self.dataTask(with: request) { data, response, error in
                    // handle SSL untrusted errors prior to any HTTP handling
                    // as these errors are NSErrors where repsonse is nil
                    if let error = error as NSError? {
                        if error.code == NSURLErrorServerCertificateUntrusted {
//                            completionHandler(nil, nil, RestError.sslCertificateUntrusted)
//                            return
                            let e = CustomError.sslTrustError(error)
                            onError(e)
                            return continuation.resume(throwing: e)
                        }
                    }
                    
                    guard let data = data, let response = response else {
                        let error = error ?? URLError(.badServerResponse)
//                        if let error = error as NSError? {
//                                        #if DEBUG
//                                        Log.debug("[REST][RESULT][ERROR][\(request.url?.absoluteString ?? "")]: \(error)")
//                                        #endif
//
//                                        if NSError.sslErrors.contains(error.code) {
//                                            completeWithResponse(.error(.notSecured))
//                                        } else {
//                                            completeWithResponse(.error(.error(error)))
//                                        }
//
//                                        return
//                                    }
                        onError(error)
                        return continuation.resume(throwing: error)
                    }
                    onSuccess(data, response)
                    continuation.resume(returning: (data, response))
                }
                dataTask?.resume()
            }
        }, onCancel: {
            onCancel()
        })
    }
}
