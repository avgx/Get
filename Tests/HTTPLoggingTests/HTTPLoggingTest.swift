import DebugThings
import Foundation
import HTTP
import Logging
import SSLPinning
import Testing

/// URLProtocol that does not complete until the task is cancelled; completion is delivered as ``URLError/cancelled``.
private final class HangUntilCancelURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "stubhangcancel"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {}

    override func stopLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
}

@Suite("HTTP logging", .serialized)
struct HTTPLoggingTests {
    @Test
    func networkLoggingDelegateGETExampleCom() async throws {
        DebugThingsTestSupport.installStandardOutputLogging()
        let taskLog = SimpleURLSessionTaskLogger(label: "http.logging.delegate")
        let (session, _) = DebugThingsTestSupport.urlSessionWithNetworkLogging(taskLogger: taskLog)
        let url = URL(string: "https://example.com")!
        let (data, response) = try await session.data(from: url, delegate: nil as URLSessionTaskDelegate?)
        let http = try #require(response as? HTTPURLResponse)
        #expect((200 ..< 300).contains(http.statusCode))
        #expect(!data.isEmpty)
    }

    @Test
    func manualSwiftLogAroundDataRequest() async throws {
        DebugThingsTestSupport.installStandardOutputLogging()
        let log = Logger(label: "http.logging.manual")
        let url = URL(string: "https://example.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        log.debug("→ \(request.httpMethod ?? "?") \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        log.debug("← \(http.statusCode) (\(data.count) bytes)")
        #expect((200 ..< 300).contains(http.statusCode))
    }

    @Test
    func networkLoggingDelegateSecondChannelLabel() async throws {
        DebugThingsTestSupport.installStandardOutputLogging()
        let taskLog = SimpleURLSessionTaskLogger(label: "http.logging.channel-b")
        let (session, _) = DebugThingsTestSupport.urlSessionWithNetworkLogging(taskLogger: taskLog)
        let url = URL(string: "https://example.com")!
        let (_, response) = try await session.data(from: url, delegate: nil as URLSessionTaskDelegate?)
        let http = try #require(response as? HTTPURLResponse)
        #expect((200 ..< 300).contains(http.statusCode))
    }

    @Test
    func networkLoggingForwardsURLSessionTaskLoggerCallbacks() async throws {
        DebugThingsTestSupport.installStandardOutputLogging()
        let recorder = RecordingURLSessionTaskLogger()
        let (session, _) = DebugThingsTestSupport.urlSessionWithNetworkLogging(taskLogger: recorder)
        let url = URL(string: "https://example.com")!
        let request = URLRequest(url: url)
        let (_, response) = try await session.dataTask(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect((200 ..< 300).contains(http.statusCode))

        let c = recorder.counts()
        #expect(c.created >= 1, "URLSessionTaskLoggerDelegate should see task creation.")
        #expect(c.dataChunks >= 1, "URLSessionDataDelegate should deliver at least one data chunk.")
        #expect(c.completed == 1, "Task should complete exactly once.")
        #expect(c.metrics >= 1, "URLSessionTaskDelegate should collect metrics when available.")
    }

    @Test
    func sessionDelegateLogsTaskCompletionWhenCancelled() async throws {
        DebugThingsTestSupport.installStandardOutputLogging()
        let recorder = RecordingURLSessionTaskLogger()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangUntilCancelURLProtocol.self] + (configuration.protocolClasses ?? [])
        let delegate = SessionDelegate(
            serverTrustPolicy: .system,
            redirectDisposition: .follow,
            handler: nil,
            logger: recorder
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "stubhangcancel://example/hang")!
        let task = session.dataTask(with: URLRequest(url: url))
        task.resume()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        try await Task.sleep(nanoseconds: 300_000_000)
        let c = recorder.counts()
        #expect(c.created >= 1)
        #expect(c.completed == 1, "Task completion must be logged even on cancel, otherwise the task looks stuck.")
    }

    @Test
    func httpClientForwardsURLSessionTaskLoggerCallbacks() async throws {
        DebugThingsTestSupport.installStandardOutputLogging()
        let recorder = RecordingURLSessionTaskLogger()
        let client = HTTPClient(
            configuration: .ephemeral,
            logger: recorder
        )
        let url = URL(string: "https://example.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await client.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect((200 ..< 300).contains(http.statusCode))
        #expect(!data.isEmpty)

        let c = recorder.counts()
        #expect(c.created >= 1, "URLSessionTaskLoggerDelegate should see task creation.")
        #expect(c.dataChunks >= 1, "URLSessionDataDelegate should deliver at least one data chunk.")
        #expect(c.completed == 1, "Task should complete exactly once.")
        #expect(c.metrics >= 1, "URLSessionTaskDelegate should collect metrics when available.")
    }

    @Test
    func httpClientForwardsRequestObserverCallbacks() async throws {
        DebugThingsTestSupport.installStandardOutputLogging()
        let recorder = RecordingRequestObserver()
        let client = HTTPClient(configuration: .ephemeral, observer: recorder)
        let url = URL(string: "https://example.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await client.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect((200 ..< 300).contains(http.statusCode))
        #expect(!data.isEmpty)

        let c = await recorder.counts()
        #expect(c.send == 1, "should see request send.")
        #expect(c.success == 1, "should deliver once")
        #expect(c.failure == 0, "should not fail")
        #expect(c.decodeFailure == 0, "should not decode-fail")

        let invalid = URL(string: "invalid-scheme://invalid-host.com")!
        request = URLRequest(url: invalid)
        request.httpMethod = "GET"
        _ = try? await client.data(for: request)

        let cc = await recorder.counts()
        #expect(cc.send == 2, "should see request send.")
        #expect(cc.failure == 1, "should fail at least once")
        #expect(cc.decodeFailure == 0)
    }
}
