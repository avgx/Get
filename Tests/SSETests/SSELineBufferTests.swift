import Foundation
import Testing

@Test func newlineBufferYieldsLines() {
    var buffer = Data("event: x\ndata: y\n\nline2\n".utf8)
    var lines: [String] = []
    while let range = buffer.range(of: Data([0x0A])) {
        let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        if let s = String(data: line, encoding: .utf8) {
            lines.append(s)
        }
    }
    #expect(lines == ["event: x", "data: y", "", "line2"])
}
