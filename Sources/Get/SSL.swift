//
//  Security.swift
//  TestPulse
//
//  Created by Alexey Govorovsky on 29.02.2024.
//

import Foundation

public enum SSL { 
    case system
    case trustEveryone
    case pinning([Pin])
}

extension SSL {
    public struct Pin: Codable, Fingerprint, Equatable {
        public let host: String
        public let serialNumber: String
        public let sha256: String
        public let sha1: String
        
        public init(host: String, serialNumber: String, sha256: String, sha1: String) {
            self.host = host
            self.serialNumber = serialNumber
            self.sha256 = sha256
            self.sha1 = sha1
        }
        
//        public init(_ other: Fingerprint) {
//            self.host = other.host
//            self.serialNumber = other.serialNumber
//            self.sha256 = other.sha256
//            self.sha1 = other.sha1
//        }
    }
}

extension SSL {
    /// Represent a single certificate.
    public struct Certificate: Fingerprint {
        let cert: SecCertificate
        public init(cert: SecCertificate) {
            self.cert = cert
        }
        
        public var commonName: String? {
            var name: CFString? = nil
            SecCertificateCopyCommonName(cert, &name)
            return name as String?
        }
        
        public var isSelfSigned: Bool? {
            return cert.isSelfSigned
        }
        
        public var emailAddresses: [String]? {
            var emails: CFArray? = nil
            SecCertificateCopyEmailAddresses(cert, &emails)
            return emails as? [String]
        }
        
        public var serialNumber: String {
            return ((SecCertificateCopySerialNumberData(cert, nil) as Data?) ?? Data()).hex(separator: ":")
        }
        
        public var subjectSummary: String? {
            return SecCertificateCopySubjectSummary(cert) as String?
        }
        
        public var data: Data {
            return SecCertificateCopyData(cert) as Data
        }
        
        public var sha256: String {
            return data.sha256().hex(separator: ":")
        }
        
        public var sha1: String {
            return data.sha1().hex(separator: ":")
        }
        
        public var pem: String {
            let lines = cert.data.base64EncodedString().split(by: 64)
            let prefix = "-----BEGIN CERTIFICATE-----"
            let suffix = "-----END CERTIFICATE-----"
            return ([ prefix ] + lines + [ suffix ]).joined(separator: "\n")
        }
        
        
    }
    
    public struct Trust {
        
        let trust: SecTrust
        public init(trust: SecTrust) {
            self.trust = trust
        }
        
        public var certificates: [Certificate] {
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
            return chain?.map { Certificate(cert: $0) } ?? []
        }
        
        public var isSelfSigned: Bool? {
            return certificates.count == 1 && (certificates.first?.isSelfSigned ?? false)
        }
        
        public func contains(_ pin: Fingerprint) -> Bool {
            return certificates.contains(where: { $0 == pin })
        }
        
//        public var pin: Pin? {
//            guard let c = certificates.first else { return nil }
//            return Pin(c)
//        }
    }
}
