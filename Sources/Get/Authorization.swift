//
//  Authorization.swift
//
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation

public typealias JwtToken = String

public enum Authorization: Sendable, CustomStringConvertible {
    case bearer(JwtToken)
    case basic(Basic)
    case insecure
    
    public struct Basic: Sendable {
        public let user: String
        public let password: String
        
        public init(user: String, password: String) {
            self.user = user
            self.password = password
        }
        
        public var userpassword: String {
            return "\(user):\(password)"
        }
        
        public var string: String {
            return userpassword.data(using: .utf8)!.base64EncodedString()
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
    
    public var userpassword: String? {
        switch self {
        case .basic(let a):
            return a.userpassword
        default:
            return nil
        }
    }
    
    public var description: String {
        switch self {
        case .bearer(let token):
            return "bearer \(token)"
        case .basic(let a):
            return "basic \(a.userpassword)"
        case .insecure:
            return "insecure"
        }
    }
    
    public var descriptionSensitive: String {
        switch self {
        case .bearer(let token):
            return "bearer ..\(token.suffix(10))"
        case .basic(let a):
            return "basic \(a.user):***"
        case .insecure:
            return "insecure"
        }
    }
}
