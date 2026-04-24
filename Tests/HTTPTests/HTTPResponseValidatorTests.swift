import HTTP
import Foundation
import RequestResponse
import Testing

@Test func validateAccepts200() throws {
    let url = URL(string: "https://example.test/ok")!
    let data = Data("{\"x\":1}".utf8)
    let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    let request = URLRequest(url: url)
    let v = DefaultResponseValidator()
    try v.validate(data: data, response: response, request: request)
}

@Test func validatePreservesErrorBodyData() throws {
    let url = URL(string: "https://example.test/err")!
    let body = #"{"error":"nope"}"#.data(using: .utf8)!
    let response = HTTPURLResponse(
        url: url,
        statusCode: 422,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    let request = URLRequest(url: url)
    let v = DefaultResponseValidator()
    do {
        try v.validate(data: body, response: response, request: request)
        Issue.record("expected throw")
    } catch let e as HTTPError {
        guard case .unacceptableStatusCode(let code, let data, let u) = e else {
            Issue.record("wrong case")
            return
        }
        #expect(code == 422)
        #expect(data == body)
        #expect(u == url)
        #expect(e.responseBody == body)
    } catch {
        Issue.record("unexpected error: \(error)")
    }
}
