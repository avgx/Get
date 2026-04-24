import Foundation

/// Controls proactive refresh before JWT `exp`. Reactive refresh on HTTP 401 is handled separately by ``AuthInterceptor``.
public struct RefreshPolicy: Sendable, Equatable {
    /// If set and positive, refresh when remaining access token lifetime is at most this value.
    /// Requires a known expiry (e.g. [JWTDecode](https://github.com/auth0/JWTDecode.swift) `jwt.expiresAt`).
    public var refreshMargin: TimeInterval?

    /// - Parameter proactiveRefreshMargin: `nil` means no proactive refresh (only 401-driven refresh via ``AuthInterceptor``).
    public init(margin: TimeInterval? = nil) {
        self.refreshMargin = margin
    }
}
