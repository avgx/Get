# Get

Swift package with modular HTTP and streaming helpers.

- **HTTPKit** — interceptors, response validation, `URLSession` async `dataTask`, error types; depends on **SSLPinning** for `URLSessionCertificateTrustFailure` (TLS helpers live there). `Package.swift` uses local `../SSLPinning` until a new SSLPinning release is tagged.
- **HTTP** — `HTTPClient` (owned `URLSession` + ``Delegate``), async `send` / `data` with [RequestResponse](https://github.com/avgx/RequestResponse); `URLSession` extensions for shared sessions; TLS via [SSLPinning](https://github.com/avgx/SSLPinning); no Pulse in the base graph.
- **GetAuth** — `AuthState`, `Authorization`, `AuthInterceptor`. For access token expiry use [JWTDecode.swift](https://github.com/auth0/JWTDecode.swift) in the app (`decode(jwt:)` → `expiresAt`); it does not validate signatures.
- **Multipart** — `MJPEGStream`, `MJPEGFrameStream`, `MultipartFrameStream` (multipart / MJPEG over HTTP); depends on **HTTP**. Product `Multipart` in `Package.swift`.
- **SSE**, **WS** — streaming / WebSocket.

Pulse and app-specific session logging are optional and live outside this package (e.g. in the app or [DebugThings](https://github.com/avgx/DebugThings)).

## Example (HTTP)

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

## License

MIT. See LICENSE.
