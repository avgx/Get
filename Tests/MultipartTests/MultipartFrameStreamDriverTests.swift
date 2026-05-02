import EncodeDecode
import Foundation
@testable import Multipart
import Testing

private let exampleURL = URL(string: "http://192.168.1.41/stream")!

@Test func multipartSessionRootThenPartWithContentLength() throws {
    let state = MultipartState()
    let outer = HTTPURLResponse(
        url: exampleURL,
        statusCode: 200,
        httpVersion: "1.1",
        headerFields: ["Content-Type": "multipart/x-mixed-replace; boundary=ngpboundary"]
    )!
    #expect(state.responseDisposition(outer) == .allow)

    let part = HTTPURLResponse(
        url: exampleURL,
        statusCode: 200,
        httpVersion: "1.1",
        headerFields: [
            "Content-Type": "image/jpeg",
            "Content-Length": "4",
        ]
    )!
    #expect(state.responseDisposition(part) == .allow)

    let body = Data([0x10, 0x20, 0x30, 0x40])
    let frames = try state.append(body)
    #expect(frames.count == 1)
    #expect(frames[0].mimeType == "image/jpeg")
    #expect(frames[0].body == body)
}

@Test func multipartSessionRejectsWrongRootMime() throws {
    let state = MultipartState()
    let outer = HTTPURLResponse(
        url: exampleURL,
        statusCode: 200,
        httpVersion: "1.1",
        headerFields: ["Content-Type": "text/plain"]
    )!
    #expect(state.responseDisposition(outer) == .cancel)
}

@Test func multipartContentTypeParsesBoundary() throws {
    let ct = "multipart/related; type=\"image/jpeg\"; boundary=\"b1\""
    let parsed = try MultipartContentType.parse(from: ct)
    #expect(parsed.mediaType == "multipart/related")
    #expect(parsed.boundary == "b1")
}

@Test func multipartRelatedParses() throws {
    let p = try MultipartContentType.parse(from: "multipart/related; boundary=r1")
    #expect(p.mediaType == "multipart/related")
    #expect(p.boundary == "r1")
}
