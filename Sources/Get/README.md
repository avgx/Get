# Get (umbrella)

Re-exports the split targets so one `import Get` pulls in **HTTP**, **Multipart**, **SSE**, **Auth**, **WS**, **RequestResponse**, and **SSLPinning**.

## `HttpClient5`

`HttpClient5` is a compatibility façade for code migrating from an older monolithic API: it owns an `HTTPClient`, a `RequestBuilder`, default JSON coders, optional static `Authorization` on the session, and SSL policy (`SSL` → `ServerTrustPolicy`).

Prefer `HTTPClient` + `RequestBuilder` directly for new code.

## See also

- [Root README.md](../../README.md)
