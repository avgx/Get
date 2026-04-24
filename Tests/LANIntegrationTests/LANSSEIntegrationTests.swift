import DebugThings
import Foundation
import HTTP
import SSE
import SSLPinning
import Testing

// MARK: - SSE (HTTPClient line stream + SSE parsing)

/// Requires `GET_TEST_SSE_PATH` (e.g. `/events`). First non-empty line from ``HTTPClient/streamLines``.
@Test(.tags(.integration))
func lanSseLineStreamFirstLine() async throws {
    guard let path = TestEnvironment.value(for: "GET_TEST_SSE_PATH"), !path.isEmpty else {
        return
    }
    guard let request = LANIntegration.basicAuthorizedGET(path: path) else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.sse.line")
    let client = HTTPClient(configuration: .ephemeral, serverTrustPolicy: .system, logger: taskLog)
    let stream = await client.streamLines(request: request)
    let line = try await LANIntegration.firstValue(in: stream)
    #expect(line != nil, "No SSE line within timeout (check GET_TEST_SSE_PATH and server).")
    guard let line else { return }
    #expect(!line.isEmpty)
}

/// Requires `GET_TEST_SSE_PATH`. First structured ``SSEEvent`` from ``HTTPClient/eventStream``.
@Test(.tags(.integration))
func lanSseEventStreamFirstEvent() async throws {
    guard let path = TestEnvironment.value(for: "GET_TEST_SSE_PATH"), !path.isEmpty else {
        return
    }
    guard let request = LANIntegration.basicAuthorizedGET(path: path) else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.sse.event")
    let client = HTTPClient(configuration: .ephemeral, serverTrustPolicy: .system, logger: taskLog)
    let stream = await client.eventStream(request: request)
    let event = try await LANIntegration.firstValue(in: stream)
    #expect(
        event != nil,
        "No SSE event within timeout (server must send a full field block ending with a blank line)."
    )
    guard let event else { return }
    #expect(event != SSEEvent(data: ""))
}

/// Requires `GET_TEST_SSE_PATH`. Reads up to 10 ``SSEEvent`` values; expects at least two distinct frames (CRLF-safe parsing).
@Test(.tags(.integration))
func lanSseEventStreamFirst10() async throws {
    guard let path = TestEnvironment.value(for: "GET_TEST_SSE_PATH"), !path.isEmpty else {
        return
    }
    guard let request = LANIntegration.basicAuthorizedGET(path: path) else {
        return
    }

    DebugThingsTestSupport.installStandardOutputLogging()
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.sse.event.10")
    let client = HTTPClient(configuration: .ephemeral, serverTrustPolicy: .system, logger: taskLog)
    var events: [SSEEvent] = []
    let stream = await client.eventStream(request: request)
    for try await event in stream {
        events.append(event)
        if events.count >= 10 {
            break
        }
    }

    #expect(events.count >= 2)
}
