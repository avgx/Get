# Get

Swift package: modular HTTP client, multipart/MJPEG streaming, Server-Sent Events, optional auth helpers, and WebSockets.

## Products (`Package.swift`)

| Product     | Purpose |
|------------|---------|
| **Get**    | Umbrella: re-exports `HTTP`, `Multipart`, `SSE`, `Auth`, `WS`, `RequestResponse`, and `SSLPinning`, plus `HttpClient5` (migration façade over `HTTPClient`). |
| **HTTP**   | `HTTPClient` (owned `URLSession` + delegate), interceptors, response validation, logging hooks, line streaming, TLS via [SSLPinning](https://github.com/avgx/SSLPinning). |
| **Multipart** | `HTTPClient.frames(...)` — async stream of `MultipartFrame` for `multipart/x-mixed-replace` / related responses (URLSession per-part delivery). |
| **SSE**    | `HTTPClient.eventStream(...)` — parsed `SSEEvent` stream. |
| **WS**     | `WebSocket` actor: `URLSessionWebSocketTask`, state stream, reconnect-oriented APIs. |

Dependencies include [RequestResponse](https://github.com/avgx/RequestResponse), [swift-log](https://github.com/apple/swift-log), [JWTDecode.swift](https://github.com/auth0/JWTDecode.swift) (JWT expiry only; not signature validation), [DebugThings](https://github.com/avgx/DebugThings), and SSLPinning.

## Umbrella import

```swift
import Get
```

Use individual products (`import HTTP`, etc.) when you want a smaller dependency surface.

## HTTP example

```swift
import HTTP
import RequestResponse

let client = HTTPClient(configuration: .ephemeral)
let builder = RequestBuilder(
    baseURL: URL(string: "https://api.github.com")!,
    encoder: JSONEncoder(),
    sessionDefaultHeaders: nil
)
let user: User = try await client.send(
    Request(path: "/user", method: .get),
    with: builder
).value
```

## Module READMEs

- [Sources/Get/README.md](Sources/Get/README.md)
- [Sources/HTTP/README.md](Sources/HTTP/README.md)
- [Sources/Multipart/README.md](Sources/Multipart/README.md)
- [Sources/SSE/README.md](Sources/SSE/README.md)
- [Sources/Auth/README.md](Sources/Auth/README.md)
- [Sources/WS/README.md](Sources/WS/README.md)

## License

MIT. See LICENSE.
