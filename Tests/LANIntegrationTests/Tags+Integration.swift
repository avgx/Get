import Testing

extension Tag {
    /// LAN / device tests (Swift **Testing** tag, not SPM package traits).
    ///
    /// Run only these tests, e.g. `swift test --filter lanHttp` or `swift test --filter lanSse`.
    ///
    /// Common variables: `GET_TEST_LAN=1`, optional `GET_TEST_HOST` (default `192.168.1.41`), `GET_TEST_USER`, `GET_TEST_PASSWORD` (without a password, network tests are skipped). You can set the same keys in `.env` at the package root (see `.env.example`); the process environment overrides `.env`.
    ///
    /// Stream tests (if a variable is unset, that test exits immediately):
    /// - `GET_TEST_SSE_PATH` — SSE path (e.g. `/events`); Basic auth same as HTTP.
    /// - `GET_TEST_MJPEG_PATH` — MJPEG / multipart over HTTP; use ``HTTPClient/frames(request:sessionConfiguration:)`` (URLSession per-part delivery).
    /// - `GET_TEST_WS_PATH` — WebSocket path (`ws://` + Basic auth as for HTTP); **WS** module.
    /// - `GET_TEST_WS_LONG_LISTEN=1` — optional 10-minute WS test (`lanWebSocketLongListenPayloadBytesAndState`); otherwise that test exits immediately.
    @Tag static var integration: Tag
}
