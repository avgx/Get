import Foundation
import HTTP

/// Attaches credentials per request. Use ``init(authorization:)`` for Basic or static Bearer; ``init(auth:)`` for refreshable Bearer JWT.
public final class AuthInterceptor: RequestInterceptor, @unchecked Sendable {
    private let auth: AuthState

    /// Bearer access token from ``AuthState`` with refresh on 401.
    public init(auth: AuthState) {
        self.auth = auth
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        let token = try await auth.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func retry(_ request: URLRequest, dueTo error: Error) async -> Bool {
        guard let http = error as? HTTPError else { return false }
        guard http.statusCodeIfUnacceptable == 401 else { return false }
        do {
            _ = try await auth.refresh()
            return true
        } catch {
            return false
        }
    }
}
