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

`WebSocket` is an actor wrapping `URLSessionWebSocketTask`. It exposes connection state, a single active `messages()` stream, and send helpers.

```swift
import WS

var request = URLRequest(url: URL(string: "wss://api.example.com/ws")!)
request.setValue("Bearer token", forHTTPHeaderField: "Authorization")

var config = WebSocket.Configuration.default
config.serverTrustPolicy = .system
config.pingInterval = 10

let socket = WebSocket(request: request, configuration: config)
let messages = await socket.messages()

await socket.connect()

for await state in await socket.connectionStateUpdates() {
    switch state {
    case .connected: break
    case .disconnected(let reason): print(reason)
    default: break
    }
}

for await message in messages {
    switch message {
    case .string(let text): print(text)
    case .data(let data): print(data.count, "bytes")
    @unknown default: break
    }
}

try await socket.sendString("{\"type\":\"ping\"}")
await socket.disconnect()
```

`WebSocket.Configuration` controls TLS, message size, handshake timeout, optional ping and read-idle timeouts, and `URLSession` connectivity settings. Presets: `.default` and `.checked` (logging, ping, shorter timeouts).

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
