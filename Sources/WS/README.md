# WS

`WebSocket` actor wrapping `URLSessionWebSocketTask`: connect / disconnect, `messages()` as `AsyncStream<URLSessionWebSocketTask.Message>`, connection state via `StateHub` (`connectionState()`, `connectionStateUpdates()`).

## Configuration

`WebSocket.Configuration` controls TLS (`ServerTrustPolicy`), message size, handshake timeout, optional ping and read-idle timeouts, timeouts and multipath-related `URLSessionConfiguration` fields.

## Dependencies

**HTTP** (shared TLS / adapter patterns), **SSLPinning**, **swift-log**, **DebugThings**.

## See also

- [Root README.md](../../README.md)
