import DebugThings
import Foundation
import HTTP
import Logging

enum DebugThingsTestSupport {
    static func installStandardOutputLogging() {
        DebugThings.bootstrapStandardOutput(level: .debug)
    }
}
