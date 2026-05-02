import Foundation
import EncodeDecode
import Testing

@Test func multipartRootParsesMixedReplaceBoundary() throws {
    let p = try MultipartContentType.parse(from: "multipart/x-mixed-replace; boundary=abc")
    #expect(p.boundary == "abc")
}

@Test func multipartRootParsesRelatedQuotedBoundary() throws {
    let p = try MultipartContentType.parse(from: "multipart/related; type=\"image/jpeg\"; boundary=\"x y\"")
    #expect(p.boundary == "x y")
}

@Test func multipartRootRejectsNonMultipart() {
    #expect(throws: MultipartError.self) {
        try MultipartContentType.parse(from: "text/plain; boundary=x")
    }
}

@Test func multipartBodyParserTwoPartsAndClose() throws {
    var raw = Data("--abc\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
    raw.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xD9])
    raw.append(contentsOf: "\r\n--abc\r\nContent-Type: text/plain\r\n\r\nZ\r\n--abc--\r\n".utf8)
    var parser = MultipartBodyParser(boundary: "abc")
    let frames = try parser.append(raw)
    #expect(frames.count == 2)
    #expect(frames[0].mimeType == "image/jpeg")
    #expect(frames[0].body == Data([0xFF, 0xD8, 0xFF, 0xD9]))
    #expect(frames[1].mimeType == "text/plain")
    #expect(frames[1].body == Data([0x5A]))
    let tail = try parser.finish(allowIncomplete: true)
    #expect(tail.isEmpty)
}

@Test func multipartBodyParserChunkedSamePayload() throws {
    var raw = Data("--abc\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
    raw.append(contentsOf: [0xFF, 0xD8, 0xFF, 0xD9])
    raw.append(contentsOf: "\r\n--abc\r\nContent-Type: text/plain\r\n\r\nZ\r\n--abc--\r\n".utf8)
    var parser = MultipartBodyParser(boundary: "abc")
    let u = Array(raw)
    var out: [MultipartFrame] = []
    for i in stride(from: 0, to: u.count, by: 3) {
        let end = min(i + 3, u.count)
        out.append(contentsOf: try parser.append(Data(u[i..<end])))
    }
    #expect(out.count == 2)
    #expect(out[0].body == Data([0xFF, 0xD8, 0xFF, 0xD9]))
    #expect(out[1].body == Data([0x5A]))
}
