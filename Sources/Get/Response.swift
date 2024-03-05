// The MIT License (MIT)
//
// Copyright (c) 2021-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A response with an associated value and metadata.
public struct Response<T> {
    /// Decoded response value.
    public let value: T
    /// Original response.
    public let response: URLResponse
    /// Response HTTP status code.
    public var statusCode: Int? { (response as? HTTPURLResponse)?.statusCode }
    /// Original response data.
    public let data: Data
    
    /// Initializes the response.
    public init(value: T, data: Data, response: URLResponse) {
        self.value = value
        self.data = data
        self.response = response
    }

    /// Returns a response containing the mapped value.
    public func map<U>(_ closure: (T) throws -> U) rethrows -> Response<U> {
        Response<U>(value: try closure(value), data: data, response: response)
    }
}

extension Response: @unchecked Sendable where T: Sendable {}
