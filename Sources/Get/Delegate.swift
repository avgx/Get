//
//  Delegate.swift
//
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation
import Pulse
import Logging

/// Automates URLSession request tracking.
final class Delegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionWebSocketDelegate {
    private let logger: NetworkLogger?
    
    //host -> certificates
    var sslCache: [String: [SSL.Certificate]] = [:]
    //private let pins: [String: SSL.Pin]
    private let ssl: SSL
    
    /// - parameter logger: By default, creates a logger with `LoggerStore.shared`.
    /// - parameter delegate: The "actual" session delegate, strongly retained.
    public init(loggerConfiguration: HttpClient5.LoggerConfiguration, ssl: SSL) {
        self.logger = loggerConfiguration.pulse
        self.ssl = ssl
        //self.pins = pins
    }
    
    // MARK: URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        logger?.logTaskCreated(task)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        logger?.logTask(task, didCompleteWithError: error)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        logger?.logTask(task, didFinishCollecting: metrics)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if task is URLSessionUploadTask {
            logger?.logTask(task, didUpdateProgress: (completed: totalBytesSent, total: totalBytesExpectedToSend))
        }
    }
    
    // MARK: URLSessionDataDelegate
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        logger?.logDataTask(dataTask, didReceive: data)
    }
    
    public func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        print(#function)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        print("prevent redirect for \(request)")
        return nil
    }
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        
        let protectionSpace = challenge.protectionSpace
        let method = protectionSpace.authenticationMethod
        let host = protectionSpace.host
        //        print("challenge \(method) for \(host)")
        guard method == NSURLAuthenticationMethodServerTrust else {
            return (.cancelAuthenticationChallenge, nil) //?? return (.performDefaultHandling, nil)
        }
        guard let serverTrust = protectionSpace.serverTrust else {
            return (.cancelAuthenticationChallenge, nil)
        }
        
        guard SecTrustGetCertificateCount(serverTrust) > 0 else {
            // This case will probably get handled by ATS, but still...
            return (.cancelAuthenticationChallenge, nil)
        }
        
        
        
        let trust = SSL.Trust(trust: serverTrust)
        self.sslCache[host] = trust.certificates

//TODO: check do i need it?
//        let isServerTrusted = SecTrustEvaluateWithError(serverTrust, nil)
//        if !isServerTrusted {
//            print("SecTrustEvaluateWithError for \(host) (is self-signed \(String(describing: trust.isSelfSigned)))")
//        }
        
        switch self.ssl {
        case .system:
            return (.performDefaultHandling, nil)
        case .pinning(let pins):
            if let pin = pins.first(where: { $0.host == host }) {
                if trust.contains(pin) {
                    return (.useCredential, URLCredential(trust: serverTrust))
                } else {
                    return (.performDefaultHandling, nil)
                }
            }
        case .trustEveryone:
            return (.useCredential, URLCredential(trust: serverTrust))
        }
        
        return (.performDefaultHandling, nil)
    }
    
    // MARK: URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol: String?) {
        Logger(label: "websocket").info("websocket didOpen \(webSocketTask.currentRequest?.url?.absoluteString ?? "-")")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Logger(label: "websocket").info("websocket didClose \(webSocketTask.currentRequest?.url?.absoluteString ?? "-")")
    }
}
