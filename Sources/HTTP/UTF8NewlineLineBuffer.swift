import Foundation

/// How to turn a line’s raw bytes into `String` when they are not valid UTF-8.
package enum UTF8InvalidLinePolicy: Sendable {
    /// Drop the line (used by ``HTTPClient/streamLines(request:sessionConfiguration:)``).
    case omitInvalidUTF8
    /// Use `""` (matches incremental SSE parsing over arbitrary chunk boundaries).
    case emptyStringForInvalidUTF8
}

/// Buffers UTF-8 `Data` and splits on `\n` (newline is not included in yielded lines).
package final class UTF8NewlineLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    package init() {}

    package func append(_ chunk: Data, policy: UTF8InvalidLinePolicy) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)
        var lines: [String] = []
        while let range = buffer.range(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            switch policy {
            case .omitInvalidUTF8:
                if let s = String(data: line, encoding: .utf8) {
                    lines.append(s)
                }
            case .emptyStringForInvalidUTF8:
                lines.append(String(data: line, encoding: .utf8) ?? "")
            }
        }
        return lines
    }

    /// Remaining bytes when the stream ends without a final `\n`.
    package func drainTailIfAny(policy: UTF8InvalidLinePolicy) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let s: String?
        switch policy {
        case .omitInvalidUTF8:
            s = String(data: buffer, encoding: .utf8)
        case .emptyStringForInvalidUTF8:
            s = String(data: buffer, encoding: .utf8) ?? ""
        }
        buffer.removeAll(keepingCapacity: false)
        return s
    }
}
