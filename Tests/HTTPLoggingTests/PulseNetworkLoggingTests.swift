// HTTPLoggingTests — HTTP + DebugThings + Pulse (SwiftLog single backend per process).
//
// If another test target already called `bootstrapStandardOutput`, `bootstrapPulse` may be a no-op for that process.
// For reliable Pulse paths, run in isolation, e.g. `swift test --filter HTTPLoggingTests`.

import DebugThings
import DebugThingsPulseProxy
import Foundation
import HTTP
import Logging
import Testing

@Suite("Pulse network logging", .serialized)
struct PulseNetworkLoggingTests {
    @Test
    func bootstrapPulseAndSwiftLogMarker() {
        DebugThings.bootstrapPulse(level: .trace)
        Logger(label: "pulse.network.test").info("pulse-bootstrap-marker")
    }

    @Test
    func networkLoggingDelegateGETWithPulseTaskLogger() async throws {
        DebugThings.bootstrapPulse(level: .trace)
        let pulse = PulseSessionEventLogger()
        let taskLogger = StreamingSkippingURLSessionTaskLogger(inner: pulse)
        let delegate = URLSessionTaskLoggerDelegate(taskLogger: taskLogger)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "https://example.com")!
        let (data, response) = try await session.data(from: url, delegate: nil as URLSessionTaskDelegate?)
        let http = try #require(response as? HTTPURLResponse)
        #expect((200 ..< 300).contains(http.statusCode))
        #expect(!data.isEmpty)
    }

    @Test
    func pulseNetworkCaptureSettingsApplyToSharedLogger() {
        var settings = PulseNetworkCaptureSettings.default
        settings.excludedHosts.insert("example.invalid")
        settings.applyToSharedNetworkLogger()
    }
}
