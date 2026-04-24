import SSE
import Testing

@Test func sseAccumulatorEmitsOnBlankLine() {
    var acc = SSEEventAccumulator()
    #expect(acc.push("id: 42") == nil)
    #expect(acc.push("event: tick") == nil)
    #expect(acc.push("data: hello") == nil)
    let ev = acc.push("")
    #expect(ev == SSEEvent(id: "42", event: "tick", data: "hello"))
}

@Test func sseAccumulatorJoinsMultipleDataLines() {
    var acc = SSEEventAccumulator()
    #expect(acc.push("data: a") == nil)
    #expect(acc.push("data: b") == nil)
    let ev = acc.push("")
    #expect(ev?.data == "a\nb")
}

@Test func sseAccumulatorFinishFlushesWithoutTrailingBlankLine() {
    var acc = SSEEventAccumulator()
    #expect(acc.push("data: tail") == nil)
    let ev = acc.finish()
    #expect(ev == SSEEvent(data: "tail"))
}

/// Lines split on `\n` only yield `"\r"` between CRLF-delimited events; must not merge blocks.
@Test func sseAccumulatorTreatsCarriageReturnOnlyLineAsEventBoundary() {
    var acc = SSEEventAccumulator()
    #expect(acc.push("event: stream-data") == nil)
    #expect(acc.push("data: one\r") == nil)
    #expect(acc.push("\r") == SSEEvent(event: "stream-data", data: "one"))
    #expect(acc.push("event: stream-data") == nil)
    #expect(acc.push("data: two") == nil)
    #expect(acc.push("\r") == SSEEvent(event: "stream-data", data: "two"))
    #expect(acc.push("event: end-of-stream") == nil)
    #expect(acc.push("data: ") == nil)
    #expect(acc.push("\r") == SSEEvent(event: "end-of-stream", data: ""))
}
