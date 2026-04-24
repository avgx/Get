import Foundation

/// One SSE message after a blank line (per [WHATWG](https://html.spec.whatwg.org/multipage/server-sent-events.html)).
public struct SSEEvent: Sendable, Equatable {
    public var id: String?
    public var event: String?
    /// Concatenated `data:` lines with `\n` between them.
    public var data: String

    public init(id: String? = nil, event: String? = nil, data: String) {
        self.id = id
        self.event = event
        self.data = data
    }
}

/// Incremental parser for `field: value` lines until an empty line.
public struct SSEEventAccumulator: Sendable {
    private var id: String?
    private var event: String?
    private var dataLines: [String] = []

    public init() {}

    /// Push one line (without trailing `\n`). Returns a complete ``SSEEvent`` when the block ends with an empty line.
    public mutating func push(_ line: String) -> SSEEvent? {
        // Splitting the body on `\n` leaves a lone `\r` for CRLF blank lines (`\r\n\r\n`); treat as empty per SSE.
        let line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        if line.isEmpty {
            defer { clear() }
            if id == nil, event == nil, dataLines.isEmpty {
                return nil
            }
            return SSEEvent(id: id, event: event, data: dataLines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") {
            return nil
        }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let field = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        switch field {
        case "id":
            id = value
        case "event":
            event = value
        case "data":
            dataLines.append(value)
        default:
            break
        }
        return nil
    }

    /// Call when the HTTP body ends to flush a block without a trailing blank line.
    public mutating func finish() -> SSEEvent? {
        push("")
    }

    private mutating func clear() {
        id = nil
        event = nil
        dataLines = []
    }
}
