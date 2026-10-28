# Get

Modular Swift package for HTTP, multipart/MJPEG streaming, Server-Sent Events, and WebSockets. Built on `URLSession` with interceptors, response validation, logging hooks, and TLS via [SSLPinning](https://github.com/avgx/SSLPinning).

**Platforms:** iOS 15+, macOS 13+, macCatalyst 15+, watchOS 9+, tvOS 15+, visionOS 1+  
**Swift tools:** 6.1+

## Products

| Product | Import | Purpose |
|---------|--------|---------|
| **Get** | `import Get` | Umbrella: re-exports **HTTP**, **Multipart**, **SSE**, **WS**, [RequestResponse](https://github.com/avgx/RequestResponse), [EncodeDecode](https://github.com/avgx/EncodeDecode), and [SSLPinning](https://github.com/avgx/SSLPinning). |
| **HTTP** | `import HTTP` | `HTTPClient`, interceptors, validation, line streaming, static auth helpers. |
| **Multipart** | `import Multipart` | `HTTPClient.frames(...)` for `multipart/x-mixed-replace` and related streams. |
| **SSE** | `import SSE` | `HTTPClient.eventStream(...)` for parsed `ServerSentEvent` values. |
| **WS** | `import WS` | `WebSocket` actor with connection state and reconnect-oriented APIs. |

Prefer individual products when you want a smaller dependency surface.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/avgx/Get.git", from: "6.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Get", package: "Get"),   // or HTTP, Multipart, SSE, WS
    ]),
]
```

---

## Get

`import Get` pulls in every module plus shared types from RequestResponse, EncodeDecode, and SSLPinning.

---

## HTTP

Core async transport: an `HTTPClient` actor owns a `URLSession` and `SessionDelegate`. Requests are built with [RequestResponse](https://github.com/avgx/RequestResponse) `Request` values and a `RequestBuilder`.

### Basic request

```swift
import HTTP
import RequestResponse

let client = HTTPClient(configuration: .ephemeral)
let builder = RequestBuilder.json(
    baseURL: URL(string: "https://api.example.com")!,
    encoder: JSONEncoder()
)

struct Version: Decodable, Sendable { let version: String }

let response = try await client.send(
    Request<Version>(path: "/product/version", method: .get),
    with: builder
)
print(response.value.version)
```

### Static authorization

Set headers on the session configuration, or use `FixedAuthInterceptor` so auth is applied per request (including streaming calls):

```swift
let client = HTTPClient(
    configuration: .ephemeral,
    interceptor: FixedAuthInterceptor(user: "admin", password: "secret")
)
```

`Authorization` supports `.bearer`, `.basic`, and `.insecure` (no header).

### Interceptors, validation, and observation

```swift
let client = HTTPClient(
    configuration: .ephemeral,
    interceptor: myInterceptor,          // adapt + retry
    validator: RequireStatus200(),      // or DefaultResponseValidator()
    observer: PathStatistics(),        // per-path metrics
    logger: SimpleURLSessionTaskLogger(label: "network"),
    serverTrustPolicy: .system,         // from SSLPinning
    maxRetryAttempts: 3
)
```

Implement `RequestInterceptor` to adapt outgoing `URLRequest` values and decide whether to retry after failures. `RequestObserver` receives will-send, success, failure, and decode-failure callbacks.

### Paged responses

For `Request<PagedResponse<T>>`, use `pages(_:with:decoder:)`. The client buffers the body and decodes from `text/event-stream` or `multipart/related` based on `Content-Type`. `send` is unavailable for `PagedResponse` requests.

```swift
import EncodeDecode

let pages: [CameraListPage] = try await client.pages(
    Request<PagedResponse<CameraListPage>>(path: "v1/cameras", method: .get),
    with: builder
)
```

### Line streaming

`streamLines(request:)` yields newline-delimited UTF-8 text over a dedicated streaming session. Retries are not applied inside the stream; use `data(for:)` when you need the interceptor retry loop.

```swift
let stream = await client.streamLines(request: urlRequest)
for try await line in stream {
    print(line)
}
```

---

## Multipart

Depends on **HTTP**. `HTTPClient.frames(request:)` returns an `AsyncThrowingStream<MultipartFrame, Error>` where URLSession delivers the outer multipart response first, then each part (e.g. MJPEG frames from `multipart/x-mixed-replace`).

```swift
import HTTP
import Multipart

let client = HTTPClient(configuration: .ephemeral)
let stream = await client.frames(request: urlRequest)

for try await frame in stream {
  let mime = frame.mimeType   // from Content-Type
  let jpeg = frame.body       // part body
}
```

Retries are not applied inside `frames`; orchestrate retries at a higher level if needed.

---

## SSE

Depends on **HTTP**. `HTTPClient.eventStream(request:)` parses Server-Sent Events into `ServerSentEvent` values (blank line separates events). Uses `streamLines` internally.

```swift
import HTTP
import SSE

let client = HTTPClient(configuration: .ephemeral)
let stream = await client.eventStream(request: urlRequest, timeout: 30)

for try await event in stream {
    if let data = event.data {
        print(data)
    }
}
```

For raw lines without SSE field parsing, use `HTTPClient.streamLines` directly.

---

## WS

`WebSocket` is an actor wrapping `URLSessionWebSocketTask`. It keeps the link up (reconnecting per `Configuration.reconnect`), publishes exactly one state at a time, and delivers frames from every connection into one `messages` stream.

```swift
import WS

var config = WebSocket.Configuration.default
config.pingInterval = 20
config.readIdleTimeout = 90
config.reconnect = .exponential(initial: 1, multiplier: 1.5, maxDelay: 30)

var logger = Logger(label: "ws")
logger[metadataKey: "ws.channel"] = "events"

let socket = WebSocket(
    request: URLRequest(url: URL(string: "wss://api.example.com/ws")!),
    configuration: config,
    requestAdapter: authInterceptor, // runs before every attempt
    logger: logger
)

// One reader for the whole lifetime of the socket: do not restart it on reconnects.
let reader = Task {
    for await message in socket.messages {
        if case .string(let text) = message { print(text) }
    }
}

// One state reader for the whole lifetime too; forward state to UI from here.
let observer = Task {
    for await state in socket.states {
        switch state {
        case .connected:
            try? await socket.sendString(#"{"subscribe":"all"}"#) // every connection is a new server session
        case .connecting, .reconnecting:
            break // no link, recovering
        case .disconnected(let reason):
            print("stopped:", reason) // no link, no more attempts until connect()
        case .idle:
            break
        }
    }
}

await socket.connect()                                  // returns at once; attempts run in the background
let outcome = await socket.firstAttemptOutcome()        // optional: .connected, .reconnecting or .disconnected
await socket.disconnect(reason: .backgroundSuspended)   // returns after the transport is torn down
await socket.connect()
await socket.shutdown()                                 // ends `messages` and `states`
```

States:

| State | Link | Meaning |
|---|---|---|
| `.idle` | no | `connect()` not called yet |
| `.connecting(attempt:)` | no | handshake in progress |
| `.connected` | yes | frames flow into `messages` |
| `.reconnecting(attempt:delay:after:)` | no | next attempt after `delay`; `after` is why the previous one ended |
| `.disconnected(reason:)` | no | stopped: `disconnect(reason:)`, terminal reason (HTTP 401/403/404/4xx), or `.never` policy |

Rules:

- `messages` and `states` each have one consumer, the owner of the socket. Cancelling the iterating task ends the stream for good. Nothing is dropped while nobody reads. `connectionState()` is a snapshot.
- `shutdownWhenLinkEnds()`, called once before `connect()`, ends both streams on the first `.disconnected`. Use it for a socket that is one session (`reconnect` is `.never`) so the message reader finishes when the link does. The owner keeps reading `states`.
- Send works only in `.connected`; nothing is queued or replayed after a reconnect.
- `connect()` / `disconnect(reason:)` from independent `Task`s run in no particular order: serialize them on the caller side.
- Per-frame traffic logging is the owner's job; `transportMetrics()` gives byte totals.

`WebSocket.Configuration` controls TLS, message size, handshake timeout, optional ping and read-idle timeouts, reconnect policy and `URLSession` connectivity settings. Presets: `.default` (one attempt, no ping) and `.checked` (10 s ping and read-idle, shorter request timeout).

---

## Dependencies

| Package | Used for |
|---------|----------|
| [RequestResponse](https://github.com/avgx/RequestResponse) | `Request`, `RequestBuilder`, `Response` |
| [EncodeDecode](https://github.com/avgx/EncodeDecode) | `PagedResponse`, `MultipartFrame`, `ServerSentEvent` |
| [SSLPinning](https://github.com/avgx/SSLPinning) | `ServerTrustPolicy`, certificate pinning |
| [swift-log](https://github.com/apple/swift-log) | Logging in HTTP and WS |
| [DebugThings](https://github.com/avgx/DebugThings) | `URLSessionTaskLogger`, network debug helpers |
| [JWTDecode.swift](https://github.com/auth0/JWTDecode.swift) | JWT expiry checks in tests (not signature validation) |

---

## License

MIT. See [LICENSE](LICENSE).
