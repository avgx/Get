//
//  File.swift
//
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation


/// Represents an error encountered by the client.
public enum CustomError: Error, LocalizedError {
    case unacceptableStatusCode(Int, String, URL)
    
    case redirectTo(URL)
    
    case sslTrustError(Error)
    //    case noInternetConnection
    //    case responseDeserialization
    //    case unknownError
    
    /// Returns the debug description.
    public var errorDescription: String? {
        switch self {
        case .unacceptableStatusCode(let statusCode, let content, let url):
            return "Response status code was unacceptable: \(statusCode). \n\(content) \n\(url.absoluteString)"
        case .redirectTo(let url):
            return "Response was redirected to \(url.absoluteString)"
        case .sslTrustError(let e):
            return e.localizedDescription
        }
    }
}


extension NSError {
    static var sslErrors: [Int] {
        return [
            NSURLErrorSecureConnectionFailed,
            NSURLErrorServerCertificateUntrusted,
            NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateNotYetValid,
            NSURLErrorServerCertificateHasUnknownRoot,
            NSURLErrorClientCertificateRejected,
            NSURLErrorClientCertificateRequired
        ]
    }
}

extension Error {
    var isSSL: Bool {
        return NSError.sslErrors.contains(where: { $0 == (self as NSError).code })
    }
}


