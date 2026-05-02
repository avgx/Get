import Foundation
import Auth
import DebugThings
import HTTP
import RequestResponse
import Testing

// MARK: - HTTP (HTTPClient + RequestBuilder)

@Test(.tags(.integration))
func lanHttpProductVersion() async throws {
    guard let (host, user, password) = LANIntegration.credentials else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    let base = URL(string: "http://\(host)")!
    let authorization = Authorization.basic(.init(user: user, password: password))
    let configuration = URLSessionConfiguration.ephemeral
    var headers: [String: String] = [
        "Accept-Encoding": "gzip, deflate, identity",
        "Accept-Language": String(Locale.current.identifier.prefix(2))
    ]
    if let authHeader = authorization.header {
        headers["Authorization"] = authHeader
    }
    configuration.httpAdditionalHeaders = headers
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.http.headers")
    let client = HTTPClient(
        configuration: configuration,
        logger: taskLog
    )
    let builder = RequestBuilder.json(
        baseURL: base,
        encoder: JSONEncoder(),
        sessionDefaultHeaders: headers
    )
    let req = Request<String>(path: "/product/version", method: .get)
    let response = try await client.send(req, with: builder)
    #expect(!response.value.isEmpty)
}

@Test(.tags(.integration))
func lanHttpAuthIntercentorProductVersion() async throws {
    guard let (host, user, password) = LANIntegration.credentials else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    let base = URL(string: "http://\(host)")!
    let authorization = Authorization.basic(.init(user: user, password: password))
    let configuration = URLSessionConfiguration.ephemeral
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.http.interceptor")
    let fixedAuth = FixedAuthInterceptor(authorization: authorization)
    let client = HTTPClient(
        configuration: configuration,
        interceptor: fixedAuth,
        logger: taskLog
    )
    let builder = RequestBuilder.json(
        baseURL: base,
        encoder: JSONEncoder()
    )
    let req = Request<String>(path: "/product/version", method: .get)
    let response = try await client.send(req, with: builder)
    #expect(!response.value.isEmpty)
}
