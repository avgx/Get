# HTTP

Core async HTTP transport built on `URLSession` with a dedicated `SessionDelegate`.

## Highlights

- **`HTTPClient`** (actor): `data(for: URLRequest)`, `data(for:with:)` / `send(...)` for [RequestResponse](https://github.com/avgx/RequestResponse) `Request` values; JSON decode in `send` with decode-failure callbacks on the observer.
- **Interceptors**: `RequestInterceptor` (`adapt`, `retry`); default `NoopRequestInterceptor`.
- **Validation**: `ResponseValidator` (default treats unacceptable HTTP status as `HTTPError`).
- **Observation**: `RequestObserver` for metrics-friendly hooks (will send, success/failure, decode failure).
- **Logging**: `URLSessionTaskLogger` (from DebugThings) wired through the delegate.
- **Streaming**: `streamLines(...)` for newline-delimited bodies (used by SSE and custom parsers).
- **TLS**: `ServerTrustPolicy` from SSLPinning; redirect behaviour via `RedirectDisposition`.
- **`Authorization`**: static Bearer / Basic header helpers (separate from refreshable JWT flow in the **Auth** product).

Multipart frame streaming and SSE live in the **Multipart** and **SSE** modules (extensions on `HTTPClient`).

## Platforms

Same as the package: iOS 15+, macOS 13+, etc. (`Package.swift`).

## See also

- [Root README.md](../../README.md)
