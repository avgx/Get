# Auth

Bearer access tokens with optional refresh, integrated as a `RequestInterceptor` on `HTTPClient`.

## Types

### `AuthState` (actor)

- Holds access and refresh tokens and optional access-token expiry (`accessExpiresAt`).
- **`validAccessToken(refreshIfNeeded:)`** — returns the current access token; may call **`refresh()`** if missing, if proactive refresh is due (`RefreshPolicy` margin vs `exp`), or when configured accordingly.
- **`refresh()`** — de-duplicates concurrent refresh via an internal `Task`; calls the closure supplied at init (`onRefresh`). Perform refresh with a **plain** `HTTPClient` (no `AuthInterceptor`) to avoid recursion.
- **`RefreshPolicy`** — optional proactive refresh margin before JWT expiry; requires a known expiry (e.g. [JWTDecode.swift](https://github.com/auth0/JWTDecode.swift) `decode(jwt:)` → `expiresAt`). JWTDecode does not validate signatures.

### `AuthInterceptor`

Conforms to **`RequestInterceptor`** (from **HTTP**).

- **`adapt`** — sets `Authorization: Bearer <token>` using `AuthState.validAccessToken()`.
- **`retry`** — on **`HTTPError`** with status **401**, calls `auth.refresh()` once and allows retry (subject to `HTTPClient`’s `maxRetryAttempts`).

Static Basic or static Bearer without refresh belongs in **`Authorization`** (HTTP module) or session default headers, not in `AuthInterceptor`.

## Wiring

```swift
import Auth
import HTTP

let auth = AuthState(policy: .init(margin: 60)) {
    // call token endpoint; return new access JWT string
    try await refreshAccessToken()
}
let client = HTTPClient(
    configuration: .ephemeral,
    interceptor: AuthInterceptor(auth: auth)
)
```

## See also

- [Root README.md](../../README.md)
