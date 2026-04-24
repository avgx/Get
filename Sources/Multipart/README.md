# Multipart

Streaming helpers for `multipart/x-mixed-replace` and similar responses (e.g. MJPEG), depending on **HTTP**.

## API

- **`HTTPClient.frames(request:sessionConfiguration:)`** — `AsyncThrowingStream<MultipartFrame, Error>` where URLSession delivers the outer multipart response first, then each part (see delegate disposition handling in `MultipartStreamHandler`).
- **`MultipartFrame`** — part headers (lower-cased field names) and body `Data`; `mimeType` helper from `Content-Type`.

Retries are not applied inside `frames`; use `HTTPClient`’s standard `data`/`send` path if you need the interceptor retry loop.

## See also

- [Root README.md](../../README.md)
