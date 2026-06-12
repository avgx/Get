import Foundation

public protocol RequestAdapter: Sendable {
    func adapt(_ request: URLRequest) async throws -> URLRequest
}

public protocol RequestRetrier: Sendable {
    func retry(_ request: URLRequest, dueTo error: Error) async -> Bool
}

/// Type that provides both `RequestAdapter` and `RequestRetrier` functionality.
public protocol RequestInterceptor: RequestAdapter, RequestRetrier {}

extension RequestInterceptor {
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        return request
    }
    
    public func retry(_ request: URLRequest, dueTo error: any Error) async -> Bool {
        return false
    }
}

public final class NoopRequestInterceptor: RequestInterceptor, Sendable {
    public init() { }
}

public final class FixedAuthInterceptor: RequestInterceptor, Sendable {
    public let authorization: Authorization
    /// Basic auth or a static Bearer header (no refresh).
    public init(authorization: Authorization) {
        self.authorization = authorization
    }
    
    public convenience init(bearerToken: String) {
        self.init(authorization: .bearer(bearerToken))
    }
    
    public convenience init(user: String, password: String) {
        self.init(authorization: .basic(.init(user: user, password: password)))
    }
    
    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        if let header = authorization.header, !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
        return request
    }
    
    public func retry(_ request: URLRequest, dueTo error: any Error) async -> Bool {
        guard let http = error as? HTTPError, let statusCode = http.statusCodeIfUnacceptable else { return false }
        
        //retry for server side errors (500/502/...)
        return statusCode >= 500
    }
}
