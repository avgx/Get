import Foundation

public actor AuthState {
    private var accessToken: String?
    private var refreshToken: String?
    private var accessExpiresAt: Date?

    private var refreshTask: Task<String, Error>?

    private var onRefresh: (@Sendable () async throws -> String)?
    private let policy: RefreshPolicy

    public init(
        policy: RefreshPolicy = .init(margin: 60),
        refresh: (@Sendable () async throws -> String)? = nil
    ) {
        self.policy = policy
        self.onRefresh = refresh
    }


    public func setTokens(access: String, refresh: String) {
        self.accessToken = access
        self.refreshToken = refresh
    }

    /// Preferred after login / refresh when JWT `exp` is known (e.g. [JWTDecode](https://github.com/auth0/JWTDecode.swift) `jwt.expiresAt` after `decode(jwt:)`).
    public func setTokens(access: String, refresh: String, accessExpiresAt: Date?) {
        self.accessToken = access
        self.refreshToken = refresh
        self.accessExpiresAt = accessExpiresAt
    }

    public func setAccessExpiration(_ date: Date?) {
        self.accessExpiresAt = date
    }

    public func getAccessToken() -> String? {
        accessToken
    }

    public func validAccessToken(refreshIfNeeded: Bool = true) async throws -> String {
        if let token = accessToken {
            if refreshIfNeeded, shouldProactivelyRefresh() {
                return try await refresh()
            }
            return token
        }
        guard refreshIfNeeded else {
            throw URLError(.unknown)
        }
        return try await refresh()
    }

    public func refresh() async throws -> String {
        if let task = refreshTask {
            return try await task.value
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }

            let newToken = try await performRefresh()
            self.accessToken = newToken
            return newToken
        }

        refreshTask = task
        return try await task.value
    }

    private func shouldProactivelyRefresh() -> Bool {
        guard let margin = policy.refreshMargin, margin > 0 else { return false }
        guard let exp = accessExpiresAt else { return false }
        let remaining = exp.timeIntervalSinceNow
        guard remaining.isFinite else { return false }
        return remaining <= margin
    }

    private func performRefresh() async throws -> String {
        guard let onRefresh else {
            throw URLError(.userAuthenticationRequired)
        }
        return try await onRefresh()
    }
}
