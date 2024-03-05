//
//  Delegate.swift
//
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation
import Pulse

/// Automates URLSession request tracking.
final class Delegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let logger: NetworkLogger?
    
    //host -> certificates
    var ssl: [String: [SSL.Certificate]] = [:]
    private let pins: [String: SSL.Pin]
    
    /// - parameter logger: By default, creates a logger with `LoggerStore.shared`.
    /// - parameter delegate: The "actual" session delegate, strongly retained.
    public init(loggerConfiguration: HttpClient5.LoggerConfiguration, pins: [String: SSL.Pin]) {
        self.logger = loggerConfiguration.pulse
        self.pins = pins
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
        
        let isServerTrusted = SecTrustEvaluateWithError(serverTrust, nil)
        
        
        let t = SSL.Trust(trust: serverTrust)
        self.ssl[host] = t.certificates
        
        if let pin = self.pins[host] {
            let isPinned = t.isPinned(pin)
            print("is pinned")
            
            if isPinned {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
        } else {
            if let pin = t.pin {
                let fingerprintToPin = [host : pin ]
                if let fingerprint = try? JSONEncoder().encode(fingerprintToPin).string() {
                    print("pin if need \(fingerprint)")
                }
            }
        }
        if !isServerTrusted {
            print("SecTrustEvaluateWithError for \(host) (is self-signed \(String(describing: t.isSelfSigned)))")
        }
        
        return (.performDefaultHandling, nil)
    }
    
}
