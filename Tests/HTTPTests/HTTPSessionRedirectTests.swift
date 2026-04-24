import Foundation
import DebugThings
import HTTP
import Testing

private struct Allow302ResponseValidator: ResponseValidator, Sendable {
    func validate(data: Data, response: URLResponse, request: URLRequest) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 302 {
            return
        }
        try DefaultResponseValidator().validate(data: data, response: response, request: request)
    }
}

/// Returns a 302 with `Location` and no body; used to verify ``RedirectDisposition/doNotFollow``.
private final class Redirect302URLProtocol: URLProtocol {
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": "https://example.com/destination"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("HTTPSession redirect", .serialized)
struct HTTPSessionRedirectTests {
    @Test
    func doNotFollowReturns302ToClient() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Redirect302URLProtocol.self] + (configuration.protocolClasses ?? [])

        let client = HTTPClient(
            configuration: configuration,
            redirectDisposition: .doNotFollow,
            validator: Allow302ResponseValidator()
        )
        let url = URL(string: "https://stub.example/resource")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await client.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 302)
        #expect(data.isEmpty)
    }

    @Test
    func sessionDelegateRetainsRedirectPolicy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Redirect302URLProtocol.self] + (configuration.protocolClasses ?? [])

        let delegate = SessionDelegate(
            redirectDisposition: .doNotFollow,
            handler: nil,
            logger: SimpleURLSessionTaskLogger()
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let url = URL(string: "https://stub.example/resource")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (_, response) = try await session.dataTask(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 302)
    }
}
