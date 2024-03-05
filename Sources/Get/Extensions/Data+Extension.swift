//
//  Data+Extension.swift
//  
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation
import CommonCrypto

extension Data {
    public func sha256() -> Data {
        let data: Data = self
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG($0.count), &hash) }
        return Data(hash)
    }
    
    public func sha1() -> Data {
        let data: Data = self
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA1($0.baseAddress, CC_LONG($0.count), &hash) }
        return Data(hash)
    }
    
    public func hex(separator: String = "") -> String {
        let data: Data = self
        return data.map { String(format: "%02X", $0) }.joined(separator: separator)
    }
    
    public func string(encoding: String.Encoding = .utf8) -> String? {
        let data: Data = self
        return String(data: data, encoding: encoding)
    }
}
