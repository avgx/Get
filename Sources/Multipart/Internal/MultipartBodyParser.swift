import Foundation

/// Incremental `multipart/*` body parser (RFC 2046 encapsulation boundaries).
struct MultipartBodyParser: Sendable {
    private let dashBoundary: [UInt8]
    private let maxBufferBytes: Int
    private var buf: [UInt8] = []
    private var needsPreambleBoundary = true
    private var isClosed = false

    private static let crlf: [UInt8] = [13, 10]
    private static let crlfcrlf: [UInt8] = [13, 10, 13, 10]
    private static let lf: [UInt8] = [10]

    init(boundary: String, maxBufferBytes: Int = 8_000_000) {
        var dash: [UInt8] = [45, 45]
        dash.append(contentsOf: Array(boundary.utf8))
        self.dashBoundary = dash
        self.maxBufferBytes = maxBufferBytes
    }

    mutating func append(_ chunk: Data) throws -> [MultipartFrame] {
        guard !isClosed else { return [] }
        buf.append(contentsOf: chunk)
        if buf.count > maxBufferBytes {
            throw MultipartError.bufferExceeded(maxBytes: maxBufferBytes)
        }
        var out: [MultipartFrame] = []
        while !isClosed {
            guard let frame = try extractOneFrame() else { break }
            out.append(frame)
        }
        return out
    }

    /// Called when the URLSession task completes. Incomplete trailing bytes are discarded without an error.
    mutating func finish(allowIncomplete: Bool = true) throws -> [MultipartFrame] {
        guard !isClosed else { return [] }
        if buf.isEmpty { return [] }
        if allowIncomplete {
            buf.removeAll(keepingCapacity: false)
            return []
        }
        throw MultipartError.unexpectedEndOfStream
    }

    private mutating func extractOneFrame() throws -> MultipartFrame? {
        if isClosed { return nil }

        if needsPreambleBoundary {
            guard let headerStart = findFirstPartHeaderStart() else { return nil }
            buf.removeSubrange(0..<headerStart)
            needsPreambleBoundary = false
        }

        guard let hdrRange = buf.firstRange(of: Self.crlfcrlf) else { return nil }
        let headersSlice = buf[0..<hdrRange.lowerBound]
        let bodyStart = hdrRange.upperBound
        guard bodyStart <= buf.count else { return nil }

        let headers = try Self.parsePartHeaders(Data(headersSlice))
        let cl = Self.parseContentLength(from: headers)

        let crlfNeedle = Self.crlf + dashBoundary
        let lfNeedle = Self.lf + dashBoundary
        let endIdx: Int
        let needleLen: Int
        if let n = cl {
            guard bodyStart + n <= buf.count else { return nil }
            endIdx = bodyStart + n
            if endIdx + crlfNeedle.count <= buf.count,
               Array(buf[endIdx..<(endIdx + crlfNeedle.count)]) == crlfNeedle
            {
                needleLen = crlfNeedle.count
            } else if endIdx + lfNeedle.count <= buf.count,
                      Array(buf[endIdx..<(endIdx + lfNeedle.count)]) == lfNeedle
            {
                needleLen = lfNeedle.count
            } else {
                return nil
            }
        } else if let e = buf.indexOf(crlfNeedle, startingAt: bodyStart) {
            endIdx = e
            needleLen = crlfNeedle.count
        } else if let e = buf.indexOf(lfNeedle, startingAt: bodyStart) {
            endIdx = e
            needleLen = lfNeedle.count
        } else {
            return nil
        }

        let body = Data(buf[bodyStart..<endIdx])

        let afterDelimiter = endIdx + needleLen

        guard afterDelimiter <= buf.count else { return nil }
        if afterDelimiter == buf.count {
            return nil
        }

        let b0 = buf[afterDelimiter]
        if b0 == 45 {
            guard afterDelimiter + 1 < buf.count else { return nil }
            guard buf[afterDelimiter + 1] == 45 else {
                throw MultipartError.unexpectedBytesAfterPartBoundary
            }
            var cut = afterDelimiter + 2
            if cut + 1 < buf.count, buf[cut] == 13, buf[cut + 1] == 10 {
                cut += 2
            } else if cut < buf.count, buf[cut] == 10 {
                cut += 1
            }
            buf.removeSubrange(0..<cut)
            isClosed = true
        } else if b0 == 13 {
            guard afterDelimiter + 1 < buf.count else { return nil }
            guard buf[afterDelimiter + 1] == 10 else {
                throw MultipartError.unexpectedBytesAfterPartBoundary
            }
            buf.removeSubrange(0..<afterDelimiter + 2)
        } else if b0 == 10 {
            buf.removeSubrange(0..<afterDelimiter + 1)
        } else {
            throw MultipartError.unexpectedBytesAfterPartBoundary
        }

        return MultipartFrame(headers: headers, body: body)
    }

    private static func parseContentLength(from headers: [String: String]) -> Int? {
        guard let raw = headers["content-length"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let n = Int(raw),
              n >= 0
        else {
            return nil
        }
        return n
    }

    private func findFirstPartHeaderStart() -> Int? {
        if buf.count >= dashBoundary.count + 2,
           Array(buf[0..<dashBoundary.count]) == dashBoundary,
           buf[dashBoundary.count] == 13, buf[dashBoundary.count + 1] == 10
        {
            return dashBoundary.count + 2
        }
        if buf.count >= dashBoundary.count + 1,
           Array(buf[0..<dashBoundary.count]) == dashBoundary,
           buf[dashBoundary.count] == 10
        {
            return dashBoundary.count + 1
        }
        let patCRLF = Self.crlf + dashBoundary + Self.crlf
        if buf.count >= patCRLF.count, let r = buf.firstRange(of: patCRLF) {
            return r.upperBound
        }
        let patLF = Self.lf + dashBoundary + Self.lf
        if buf.count >= patLF.count, let r = buf.firstRange(of: patLF) {
            return r.upperBound
        }
        return nil
    }

    private static func parsePartHeaders(_ data: Data) throws -> [String: String] {
        guard let s = String(data: data, encoding: .isoLatin1) else {
            throw MultipartError.malformedPartHeaders
        }
        var out: [String: String] = [:]
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if t.first == " " || t.first == "\t" { continue }
            guard let colon = t.firstIndex(of: ":") else {
                throw MultipartError.malformedPartHeaders
            }
            let name = String(t[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            out[name] = value
        }
        return out
    }
}

private extension [UInt8] {
    func firstRange(of needle: [UInt8]) -> Range<Int>? {
        guard !needle.isEmpty, count >= needle.count else { return nil }
        outer: for i in 0...(count - needle.count) {
            for j in 0..<needle.count {
                if self[i + j] != needle[j] { continue outer }
            }
            return i..<(i + needle.count)
        }
        return nil
    }

    func indexOf(_ needle: [UInt8], startingAt: Int) -> Int? {
        guard startingAt < count else { return nil }
        guard let r = Array(self[startingAt...]).firstRange(of: needle) else { return nil }
        return startingAt + r.lowerBound
    }
}
