//
//  File.swift
//  
//
//  Created by Alexey Govorovsky on 04.03.2024.
//

import Foundation
import Pulse

extension HttpClient5 {
    public enum LoggerConfiguration: String, CaseIterable {
        case none
        case sensitive
        case full
    }
}

extension HttpClient5.LoggerConfiguration {
    var pulse: NetworkLogger? {
        switch self {
        case .full:
            return fullPulseLogger
        case .sensitive:
            return sensitivePulseLogger
        case .none:
            return nil
        }
    }
}

fileprivate let fullPulseLogger = NetworkLogger()

fileprivate let sensitivePulseLogger = NetworkLogger {
//    // Includes only requests with the given domain.
//    $0.includedHosts = ["*.example.com"]
//
//
//    // Exclude some subdomains.
//    $0.excludedHosts = ["logging.example.com"]


    // Exclude specific URLs.
//    $0.excludedURLs = ["*/log/event"]


    // Replaces values for the given HTTP headers with "<private>"
    $0.sensitiveHeaders = ["Authorization", "Access-Token"]


    // Redacts sensitive query items.
    $0.sensitiveQueryItems = ["password", "token", "auth_token", "authToken"]

    // Replaces values for the given response and request JSON fields with "<private>"
    $0.sensitiveDataFields = ["password", "accessToken", "refreshToken"]
}


//TODO: maybe some day
//
//import Logging
//
//extension Logger {
//    func assert(
//        _ condition: @autoclosure () -> Bool,
//        _ message: @autoclosure () -> String = String(),
//        file: StaticString = #file,
//        function: String = #function,
//        line: UInt = #line
//    ) {
//        if condition() {
//            assertionFailure(message(), file: file, function: function, line: line)
//        }
//    }
//
//    func precondition(
//        _ condition: @autoclosure () -> Bool,
//        _ message: @autoclosure () -> String = String(),
//        file: StaticString = #file,
//        function: String = #function,
//        line: UInt = #line
//    ) {
//        if condition() {
//            preconditionFailure(message(), file: file, function: function, line: line)
//        }
//    }
//
//    func assertionFailure(
//        _ message: @autoclosure () -> String = String(),
//        file: StaticString = #file,
//        function: String = #function,
//        line: UInt = #line
//    ) {
//        let message = message()
//        error("\(message)", file: "\(file)", function: function, line: line)
//        Swift.assertionFailure(message, file: file, line: line)
//    }
//
//    func preconditionFailure(
//        _ message: @autoclosure () -> String = String(),
//        file: StaticString = #file,
//        function: String = #function,
//        line: UInt = #line
//    ) -> Never {
//        let message = message()
//        critical("\(message)", file: "\(file)", function: function, line: line)
//        return Swift.preconditionFailure(message, file: file, line: line)
//    }
//
//    func fatalError(
//        _ message: @autoclosure () -> String = String(),
//        file: StaticString = #file,
//        function: String = #function,
//        line: UInt = #line
//    ) -> Never {
//        let message = message()
//        critical("\(message)", file: "\(file)", function: function, line: line)
//        return Swift.fatalError(message, file: file, line: line)
//    }
//}
