//
//  Websocket5.swift
//
//
//  Created by Alexey Govorovsky on 11.03.2024.
//  https://obscuredpixels.com/awaiting-websockets-in-swiftui
//  https://www.donnywals.com/iterating-over-web-socket-messages-with-async-await-in-swift/
//  https://github.com/tidwall/SwiftWebSocket/blob/master/Source/WebSocket.swift

import Foundation
import Logging

public typealias WsStream = AsyncThrowingStream<URLSessionWebSocketTask.Message, Error>

public class WebSocketStream: AsyncSequence {
    public typealias AsyncIterator = WsStream.Iterator
    public typealias Element = URLSessionWebSocketTask.Message

    private var continuation: WsStream.Continuation?
    private let uuid: Int
    private let task: URLSessionWebSocketTask
    private let encoder: JSONEncoder
    
    private lazy var stream: WsStream = {
        return WsStream { continuation in
            self.continuation = continuation
            waitForNextValue()
        }
    }()

    private func waitForNextValue() {
        guard task.closeCode == .invalid else {
            continuation?.finish()
            return
        }

        task.receive(completionHandler: { [weak self] result in
            guard let continuation = self?.continuation else {
                return
            }

            do {
                let message = try result.get()
                continuation.yield(message)
                self?.waitForNextValue()
            } catch {
                continuation.finish(throwing: error)
            }
        })
    }

    public init(task: URLSessionWebSocketTask, encoder: JSONEncoder = JSONEncoder(), uuid: Int = 0) {
        self.uuid = uuid
        self.task = task
        self.encoder = encoder
        task.resume()
        Logger(label: "lifecycle").info("\(String(describing: self)) \(uuid)")
    }

    deinit {
        continuation?.finish()
        let uuid = self.uuid
        Logger(label: "lifecycle").info("~\(String(describing: self))  \(uuid)")
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return stream.makeAsyncIterator()
    }

    public func cancel() async throws {
        task.cancel(with: .goingAway, reason: nil)
        continuation?.finish()
    }
    
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await task.send(message)
    }
    
    public func send<T: Encodable>(_ data: T) async throws {
        let data = try self.encoder.encode(data)
        guard let str = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        try await send(.string(str))
    }
}

