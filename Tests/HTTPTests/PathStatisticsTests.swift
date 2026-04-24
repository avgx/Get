import Foundation
import HTTP
import Testing

@Suite("PathStatistics")
struct PathStatisticsTests {
    @Test
    func aggregatesWillSendSuccessAndBytesByPath() async throws {
        let stats = PathStatistics()
        let url = URL(string: "https://example.org/api/v1/items")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data([1, 2, 3])

        await stats.willSend(req)
        let body = Data("ok".utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        await stats.didCompleteSuccess(req, response: response, body: body, duration: 0.15)

        let snap = await stats.snapshot()
        let path = PathStatistics.pathKey(for: req)
        #expect(path == "/api/v1/items")
        let bucket = try #require(snap[path])
        #expect(bucket.willSendCount == 1)
        #expect(bucket.httpSuccessCount == 1)
        #expect(bucket.httpFailureCount == 0)
        #expect(bucket.decodeFailureCount == 0)
        #expect(bucket.statusCodeCounts[200] == 1)
        #expect(bucket.totalRequestBodyBytesSent == 3)
        #expect(bucket.totalResponseBodyBytesReceived == 2)
        #expect(bucket.successDurationSum == 0.15)
        #expect(bucket.averageSuccessDuration == 0.15)
    }

    @Test
    func decodeFailureIncrementsWithoutDoubleCountingBody() async throws {
        let stats = PathStatistics()
        let url = URL(string: "https://example.org/data")!
        let req = URLRequest(url: url)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        let body = Data([9, 9])

        await stats.willSend(req)
        await stats.didCompleteSuccess(req, response: response, body: body, duration: 0.05)
        struct FakeDecode: Error {}
        await stats.didDecodeFailure(req, response: response, body: body, expectedDecodableTypeName: "Foo", error: FakeDecode())

        let path = PathStatistics.pathKey(for: req)
        let snap = await stats.snapshot()
        let bucket = try #require(snap[path])
        #expect(bucket.httpSuccessCount == 1)
        #expect(bucket.decodeFailureCount == 1)
        #expect(bucket.totalResponseBodyBytesReceived == 2)
    }

    @Test
    func resetClearsSnapshot() async {
        let stats = PathStatistics()
        let req = URLRequest(url: URL(string: "https://a.test/")!)
        await stats.willSend(req)
        await stats.reset()
        let snap = await stats.snapshot()
        #expect(snap.isEmpty)
    }
}
