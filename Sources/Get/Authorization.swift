//
//  Authorization.swift
//
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation

public typealias JwtToken = String

public enum Authorization: CustomStringConvertible {
    case bearer(JwtToken)
    case basic(Basic)
    case insecure
    
    public struct Basic {
        public let user: String
        public let password: String
        
        public init(user: String, password: String) {
            self.user = user
            self.password = password
        }
        
        public var string: String {
            return "\(user):\(password)".data(using: .utf8)!.base64EncodedString()
        }
    }

    
    public var header: String? {
        switch self {
        case .bearer(let token):
            return "Bearer \(token)"
        case .basic(let a):
            return "Basic \(a.string)"
        case .insecure:
            return nil
        }
    }
    
    public var token: String? {
        switch self {
        case .bearer(let token):
            return "\(token)"
        default:
            return nil
        }
    }
    
    public var description: String {
        switch self {
        case .bearer(let token):
            return "bearer \(token)"
        case .basic(let a):
            return "basic \(a.string)"
        case .insecure:
            return "insecure"
        }
    }
}
