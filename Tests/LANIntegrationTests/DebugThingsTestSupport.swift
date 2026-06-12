import Foundation
import DebugThings
import HTTP
import Logging

enum DebugThingsTestSupport {
    static func installStandardOutputLogging() {
        DebugThings.bootstrapStandardOutput(level: .debug)
    }
}
