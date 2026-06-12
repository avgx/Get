# SSE

Server-Sent Events on top of **HTTP**’s line streaming.

## API

- **`HTTPClient.eventStream(request:timeout:sessionConfiguration:)`** — `AsyncThrowingStream<SSEEvent, Error>`; blank line separates events; parsing via `SSEEvent` / accumulator types in this module.

Uses `HTTPClient.streamLines` internally.

## See also

- [Root README.md](../../README.md)
