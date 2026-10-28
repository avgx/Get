import CryptoKit
import Foundation
import Network

/// Minimal TCP server on 127.0.0.1 for WebSocket client tests. No external network involved.
///
/// - `silent`: accepts and never answers (handshake timeout).
/// - `httpStatus`: answers the upgrade with a plain HTTP status and closes.
/// - `webSocket`: completes the upgrade, sends one text frame `hello <n>` (`n` = connection number from 1),
///   then optionally sends a close frame (1001) after `closeAfter` seconds and drops the TCP connection.
final class LocalServer: @unchecked Sendable {
    enum Mode: Sendable {
        case silent
        case httpStatus(Int)
        case webSocket(closeAfter: TimeInterval?)
    }

    private let mode: Mode
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalServer")
    private let lock = NSLock()
    private var heads: [String] = []
    private var connections: [NWConnection] = []

    init(mode: Mode) throws {
        self.mode = mode
        self.listener = try NWListener(using: .tcp, on: .any)
    }

    /// Starts listening; returns the bound port.
    func start() async throws -> UInt16 {
        let listener = self.listener
        let once = Once()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// Stops listening and drops every connection.
    func stop() {
        listener.cancel()
        lock.lock()
        let all = connections
        connections.removeAll()
        lock.unlock()
        for connection in all {
            connection.cancel()
        }
    }

    /// Request heads (request line + headers) received so far, in order.
    var requestHeads: [String] {
        lock.lock()
        defer { lock.unlock() }
        return heads
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        readHead(connection, buffer: Data())
    }

    private func readHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                self.respond(connection, head: head)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readHead(connection, buffer: buffer)
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        lock.lock()
        heads.append(head)
        let number = heads.count
        lock.unlock()

        switch mode {
        case .silent:
            drain(connection)
        case .httpStatus(let status):
            let response = "HTTP/1.1 \(status) Test\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        case .webSocket(let closeAfter):
            guard let key = Self.header("Sec-WebSocket-Key", in: head) else {
                connection.cancel()
                return
            }
            let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)))
                .base64EncodedString()
            var payload = Data(
                "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8
            )
            payload.append(Self.textFrame("hello \(number)"))
            connection.send(content: payload, completion: .contentProcessed { _ in })
            drain(connection)
            if let closeAfter {
                queue.asyncAfter(deadline: .now() + closeAfter) {
                    connection.send(content: Data([0x88, 0x02, 0x03, 0xE9]), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        }
    }

    /// Reads and ignores everything the client sends.
    private func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] _, _, isComplete, error in
            guard !isComplete, error == nil else { return }
            self?.drain(connection)
        }
    }

    static func header(_ name: String, in head: String) -> String? {
        for line in head.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            if line[..<colon].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame {
                return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func textFrame(_ text: String) -> Data {
        let bytes = Array(text.utf8)
        precondition(bytes.count < 126)
        return Data([0x81, UInt8(bytes.count)] + bytes)
    }
}

/// Runs a closure at most once, from any thread.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
