import Foundation
import EncodeDecode
import HTTP

/// When URLSession delivers each multipart **part** as its own `HTTPURLResponse` (typical for `multipart/x-mixed-replace` on Apple stacks), accumulate `didReceive data` until `Content-Length` is satisfied, or scan for a JPEG (`FF D8` … `FF D9`) when length is unknown.
///
/// Root response must be `multipart/x-mixed-replace` (same contract as the legacy `URLSessionDataDelegate` path). `multipart/related` uses the same delegate ordering; frames are yielded incrementally like `x-mixed-replace`.
final class MultipartState: @unchecked Sendable {
    private let lock = NSLock()
    private var partHeaders: [String: String] = [:]
    private var buffer = Data()
    private var expectedTotal: Int?
    private var useKnownLength = true
    private var queued: [MultipartFrame] = []
    private var sessionFatal: Error?
    private var hasActivePart = false
    private var validatedRootMIME = false

    init() {}

    public func responseDisposition(_ http: HTTPURLResponse) -> URLSession.ResponseDisposition {
        lock.lock()
        defer { lock.unlock() }
        if sessionFatal != nil { return .cancel }

        if !validatedRootMIME {
            validatedRootMIME = true
            guard http.statusCode == 200 else {
                sessionFatal = MultipartError.httpNotOK(statusCode: http.statusCode)
                return .cancel
            }
            guard http.mimeType?.lowercased() == "multipart/x-mixed-replace" else {
                sessionFatal = MultipartError.invalidRootContentType
                return .cancel
            }
        } else {
            guard http.statusCode == 200 else {
                sessionFatal = MultipartError.httpNotOK(statusCode: http.statusCode)
                return .cancel
            }
        }

        if hasActivePart {
            if useKnownLength, let exp = expectedTotal, exp > 0, buffer.count > 0, buffer.count < exp {
                sessionFatal = MultipartError.urlSessionPartIncomplete
                return .cancel
            }
            if !useKnownLength, !buffer.isEmpty {
                if let pair = Self.extractFirstJPEG(from: buffer) {
                    queued.append(MultipartFrame(headers: partHeaders, body: pair.jpeg))
                    buffer = pair.remainder
                } else {
                    buffer = Data()
                }
            }
        }

        partHeaders = http.normalizedHeaders()
        let len = http.expectedContentLength
        if len < 0 {
            useKnownLength = false
            expectedTotal = nil
        } else {
            useKnownLength = true
            let asInt = Int(len)
            expectedTotal = asInt
            if asInt > 0 {
                buffer.reserveCapacity(min(asInt, 16_000_000))
            }
        }
        hasActivePart = true
        return .allow
    }

    public func append(_ chunk: Data) throws -> [MultipartFrame] {
        lock.lock()
        defer { lock.unlock() }
        if let e = sessionFatal {
            throw e
        }
        var out: [MultipartFrame] = []
        out.append(contentsOf: queued)
        queued.removeAll(keepingCapacity: false)

        guard hasActivePart else {
            return out
        }

        buffer.append(chunk)
        if buffer.count > 16_000_000 {
            throw MultipartError.bufferExceeded(maxBytes: 16_000_000)
        }

        if useKnownLength, let exp = expectedTotal, exp > 0, buffer.count >= exp {
            let body = Data(buffer.prefix(exp))
            buffer.removeFirst(exp)
            out.append(MultipartFrame(headers: partHeaders, body: body))
            expectedTotal = nil
            partHeaders = [:]
        } else if !useKnownLength {
            while let pair = Self.extractFirstJPEG(from: buffer) {
                out.append(MultipartFrame(headers: partHeaders, body: pair.jpeg))
                buffer = pair.remainder
            }
        }

        return out
    }

    public func finish() throws -> [MultipartFrame] {
        lock.lock()
        defer { lock.unlock() }
        if let e = sessionFatal {
            throw e
        }
        var out: [MultipartFrame] = []
        out.append(contentsOf: queued)
        queued.removeAll(keepingCapacity: false)
        if hasActivePart, !useKnownLength, !buffer.isEmpty, let pair = Self.extractFirstJPEG(from: buffer) {
            out.append(MultipartFrame(headers: partHeaders, body: pair.jpeg))
            buffer = pair.remainder
        }
        return out
    }

    public func takeFatalError() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        let e = sessionFatal
        sessionFatal = nil
        return e
    }

    // MARK: - JPEG scan (unknown Content-Length)

    private static func extractFirstJPEG(from data: Data) -> (jpeg: Data, remainder: Data)? {
        let bytes = [UInt8](data)
        guard let soi = firstSOI(bytes) else { return nil }
        guard let endExclusive = firstEOIEnd(bytes, start: soi) else { return nil }
        let jpeg = Data(bytes[soi..<endExclusive])
        let remainder = endExclusive < bytes.count ? Data(bytes[endExclusive...]) : Data()
        return (jpeg, remainder)
    }

    private static func firstSOI(_ bytes: [UInt8]) -> Int? {
        var i = 0
        while i + 1 < bytes.count {
            if bytes[i] == 0xFF, bytes[i + 1] == 0xD8 { return i }
            i += 1
        }
        return nil
    }

    /// Byte index **after** `FF D9` (exclusive end for slicing from `soi`).
    private static func firstEOIEnd(_ bytes: [UInt8], start: Int) -> Int? {
        var i = start + 2
        while i + 1 < bytes.count {
            if bytes[i] == 0xFF, bytes[i + 1] == 0xD9 {
                return i + 2
            }
            i += 1
        }
        return nil
    }
}
