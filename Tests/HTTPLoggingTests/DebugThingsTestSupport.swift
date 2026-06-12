import Foundation
import DebugThings
import HTTP
import Logging

enum DebugThingsTestSupport {
    static func installStandardOutputLogging() {
        DebugThings.bootstrapStandardOutput(level: .debug)
    }

    static func urlSessionWithNetworkLogging(
        configuration: URLSessionConfiguration = .ephemeral,
        taskLogger: any URLSessionTaskLogger
    ) -> (session: URLSession, delegate: URLSessionTaskLoggerDelegate) {
        let delegate = URLSessionTaskLoggerDelegate(taskLogger: taskLogger)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return (session, delegate)
    }
}
