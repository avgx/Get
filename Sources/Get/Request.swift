// The MIT License (MIT)
//
// Copyright (c) 2021-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// An HTTP network request.
public struct Request<Response>: @unchecked Sendable {
    /// HTTP method, e.g. "GET".
    public var method: HTTPMethod
    /// Resource URL. Relative to baseURL.
    public var path: String
    /// Request query items.
    public var query: [(String, String?)]?
    /// Request body.
    public var body: Encodable?
    /// Request headers to be added to the request.
    public var headers: [String: String]?
    /// ID provided by the user. Not used by the API client.
    public var id: String?

    /// Initializes the request with the given parameters.
    public init(
        path: String,
        method: HTTPMethod = .get,
        query: [(String, String?)]? = nil,
        body: Encodable? = nil,
        headers: [String: String]? = nil,
        id: String? = nil
    ) {
        self.method = method
        self.path = path.isEmpty ? "/" : path
        self.query = query
        self.headers = headers
        self.body = body
        self.id = id
    }

}

extension Request where Response == Void {
    /// Initialiazes the request with the given parameters.
    public init(
        path: String,
        method: HTTPMethod = .get,
        query: [(String, String?)]? = nil,
        body: Encodable? = nil,
        headers: [String: String]? = nil,
        id: String? = nil
    ) {
        self.method = method
        self.path = path.isEmpty ? "/" : path
        self.query = query
        self.headers = headers
        self.body = body
        self.id = id
    }
}

public struct HTTPMethod: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let get: HTTPMethod = "GET"
    public static let post: HTTPMethod = "POST"
    public static let patch: HTTPMethod = "PATCH"
    public static let put: HTTPMethod = "PUT"
    public static let delete: HTTPMethod = "DELETE"
    public static let options: HTTPMethod = "OPTIONS"
    public static let head: HTTPMethod = "HEAD"
    public static let trace: HTTPMethod = "TRACE"
}
