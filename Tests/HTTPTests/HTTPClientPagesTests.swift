import Foundation
import RequestResponse
import Testing
@testable import HTTP

private struct PageModel: Codable, Sendable, Equatable {
    let name: String
}

private let stubHost = "pages-stub.test"

private final class PagesStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var contentType = "text/event-stream"

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == stubHost
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("HTTPClient.pages", .serialized)
struct HTTPClientPagesTests {
    private let builder = RequestBuilder.json(
        baseURL: URL(string: "https://\(stubHost)/")!,
        encoder: JSONEncoder()
    )

    private func makeClient() -> HTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PagesStubURLProtocol.self] + (configuration.protocolClasses ?? [])
        return HTTPClient(configuration: configuration)
    }

    @Test func decodePagedBody_sse() throws {
        let body = """
        event: stream-data
        data: {"name":"n1"}

        event: stream-data
        data: {"name":"n2"}

        """.data(using: .utf8)!

        let pages = try HTTPClient.decodePagedBody(
            PageModel.self,
            contentType: "text/event-stream",
            from: body,
            using: JSONDecoder()
        )
        #expect(pages == [PageModel(name: "n1"), PageModel(name: "n2")])
    }

    @Test func decodePagedBody_sseCaseInsensitiveMediaType() throws {
        let body = """
        event: stream-data
        data: {"name":"crlf"}

        """.data(using: .utf8)!

        let pages = try HTTPClient.decodePagedBody(
            PageModel.self,
            contentType: "Text/Event-Stream; charset=utf-8",
            from: body,
            using: JSONDecoder()
        )
        #expect(pages == [PageModel(name: "crlf")])
    }

    @Test func decodePagedBody_multipartRelated() throws {
        let boundary = "testb"
        let contentType = "multipart/related; boundary=\(boundary)"
        var body = Data()
        body.append(contentsOf: "\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8)
        body.append(Data(#"{"name":"a"}"#.utf8))
        body.append(contentsOf: "\r\n--\(boundary)\r\nContent-Type: application/json\r\n\r\n".utf8)
        body.append(Data(#"{"name":"b"}"#.utf8))

        let pages = try HTTPClient.decodePagedBody(
            PageModel.self,
            contentType: contentType,
            from: body,
            using: JSONDecoder()
        )
        #expect(pages == [PageModel(name: "a"), PageModel(name: "b")])
    }

    @Test func decodePagedBody_unknownContentType() throws {
        let body = Data(#"{"name":"x"}"#.utf8)

        #expect(throws: URLError.self) {
            try HTTPClient.decodePagedBody(
                PageModel.self,
                contentType: "application/json",
                from: body,
                using: JSONDecoder()
            )
        }
    }

    @Test func pages_sseEndToEnd() async throws {
        PagesStubURLProtocol.body = """
        event: stream-data
        data: {"name":"live"}

        event: end-of-stream
        data: {}

        """.data(using: .utf8)!
        PagesStubURLProtocol.contentType = "text/event-stream"

        let client = makeClient()
        let pages = try await client.pages(
            Request<PagedResponse<PageModel>>(path: "v1/domain/cameras"),
            with: builder
        )
        #expect(pages == [PageModel(name: "live")])
    }

    @Test func pages_multipartRelatedEndToEnd() async throws {
        let boundary = "ngpboundary"
        var body = Data()
        body.append(contentsOf: "--\(boundary)\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n".utf8)
        body.append(Data(#"{"name":"part"}"#.utf8))
        body.append(contentsOf: "\r\n--\(boundary)--\r\n".utf8)

        PagesStubURLProtocol.body = body
        PagesStubURLProtocol.contentType = "multipart/related; boundary=\(boundary)"

        let client = makeClient()
        let pages = try await client.pages(
            Request<PagedResponse<PageModel>>(path: "v1/domain/cameras"),
            with: builder
        )
        #expect(pages == [PageModel(name: "part")])
    }
}
