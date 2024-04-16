// The MIT License (MIT)
//
// Copyright (c) 2021-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Logging

fileprivate let appStartTs = Date()

extension URLSessionConfiguration {
    public class var custom: URLSessionConfiguration {
        let x: URLSessionConfiguration = .ephemeral
        x.timeoutIntervalForRequest = 10
        x.timeoutIntervalForResource = 30
        x.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return x
    }
}

/// Performs network requests constructed using ``Request``.
public actor HttpClient5 {
    let uuid = Int(Date().timeIntervalSince(appStartTs) * 1_000)
    
    private let authorization: Authorization
    
    /// The underlying `URLSession` instance.
    public nonisolated let session: URLSession

    /// A base URL. For example, `"https://api.github.com"`.
    public nonisolated let baseURL: URL
    
    /// The (optional) URLSession delegate that allows you to monitor the underlying URLSession.
    private let sessionDelegate: Delegate?
    /// Overrides the default delegate queue.
    private let sessionDelegateQueue: OperationQueue?
    /// By default, uses `.iso8601` date decoding strategy.
    private let decoder: JSONDecoder
    /// By default, uses `.iso8601` date encoding strategy.
    private let encoder: JSONEncoder
    
    
    deinit {
        let uuid = self.uuid
//        print("~\(String(describing: self))  \(uuid)")
        Logger(label: "lifecycle").info("~\(String(describing: self)) \(uuid)")
    }
    
    public func finishTasksAndInvalidate() {
        self.session.finishTasksAndInvalidate()
    }
    
    public func certificates(for host: String) -> [SSL.Certificate]? {
        return sessionDelegate?.sslCache[host]
    }
    
    /// Initializes the client with the given parameters.
    ///
    /// - parameter baseURL: A base URL. For example, `"https://api.github.com"`.
    public init(baseURL: URL, authorization: Authorization = .insecure, sessionConfiguration: URLSessionConfiguration = .custom, loggerConfiguration: LoggerConfiguration = .sensitive, ssl: SSL = .system) {
        self.authorization = authorization
        
        self.baseURL = baseURL
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601    //.secondsSince1970
        self.decoder.dataDecodingStrategy = .base64
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601    //.secondsSince1970
        self.encoder.dataEncodingStrategy = .base64
        //TODO: .formatted(DateFormatter)
        self.encoder.outputFormatting = [ .withoutEscapingSlashes, .prettyPrinted ]
        
//        self.sessionConfiguration = sessionConfiguration
        let configuration = sessionConfiguration
        
        if let authHeader = authorization.header {
            configuration.httpAdditionalHeaders = [
                "Authorization": authHeader,
                "Accept-Encoding": "gzip, deflate, identity",
                "Accept-Language": Locale.current.identifier.prefix(2)
            ]
        }
        sessionDelegate = Delegate(loggerConfiguration: loggerConfiguration, ssl: ssl)
        sessionDelegateQueue = .serial() //TODO: may be nil?
        self.session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: sessionDelegateQueue)
        
//        if authorization.isExpired {
//            Logger(label: "network").error("create httpclient3 with expired token \(authorization)")
//        }
        let uuid = self.uuid
//        print("\(String(describing: self)) \(uuid) \(baseURL.absoluteString) \(authorization.description)")
        Logger(label: "lifecycle").info("\(String(describing: self)) \(uuid) \(authorization.description)")
    }
    

    // MARK: Sending Requests

    /// Sends the given request and returns a decoded response.
    ///
    /// - parameters:
    ///   - request: The request to perform.
    ///
    /// - returns: A response with a decoded body. If the response type is
    /// optional and the response body is empty, returns `nil`.
    @discardableResult public func send<T: Decodable>( _ request: Request<T>) async throws -> Response<T> {
        let response = try await data(for: request)
        let decoder = self.decoder
        let value: T = try await decode(response.data, using: decoder)
        return response.map { _ in value }
    }

    /// Sends the given request.
    ///
    /// - parameters:
    ///   - request: The request to perform.
    ///
    /// - returns: A response with an empty value.
    @discardableResult public func send(_ request: Request<Void>) async throws -> Response<Void> {
        try await data(for: request).map { _ in () }
    }

    // MARK: Fetching Data

    /// Fetches data for the given request.
    ///
    /// - parameters:
    ///   - request: The request to perform.
    ///
    /// - returns: A response with a raw response data.
    public func data<T>(for request: Request<T>) async throws -> Response<Data> {
        let request = try await makeURLRequest(for: request)
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        
        let (data, httpResponse) = try await session.dataTask(for: request)
        //TODO: непрокатило let (data, httpResponse) = try await session.data(for: request, delegate: session.delegate as? URLSessionTaskDelegate)
        
        let response = Response(value: data, data: data, response: httpResponse)
        
        //validate
        let statusCode = response.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if 302 == statusCode || 301 == statusCode,
               let location = (response.response as? HTTPURLResponse)?.allHeaderFields["Location"] as? String,
               let redirected = URL(string: location) {
                throw CustomError.redirectTo(redirected)
            }
            let s = String(data: response.data, encoding: .utf8) ?? ""
            throw CustomError.unacceptableStatusCode(statusCode, s, response.response.url ?? url)
        }
        
        return response
    }

    // MARK: Making Requests

    /// Creates `URLRequest` for the given request.
    public func makeURLRequest<T>(for request: Request<T>) async throws -> URLRequest {
        
        let url = try makeURL(for: request)
        var urlRequest = URLRequest(url: url)
        urlRequest.allHTTPHeaderFields = request.headers
        urlRequest.httpMethod = request.method.rawValue
        if let body = request.body {
            let encoder = self.encoder
            urlRequest.httpBody = try await encode(body, using: encoder)
            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil &&
                session.configuration.httpAdditionalHeaders?["Content-Type"] == nil {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        if urlRequest.value(forHTTPHeaderField: "Accept") == nil &&
            session.configuration.httpAdditionalHeaders?["Accept"] == nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        
        return urlRequest
    }

    private func makeURL<T>(for request: Request<T>) throws -> URL {
        let baseFix = baseURL.absoluteString.hasSuffix("/")
            ? baseURL.absoluteString
            : baseURL.absoluteString + "/"
        let pathFix = request.path.hasPrefix("/")
            ? String(request.path.dropFirst())
            : request.path
        let resultUrl = URL(string: baseFix + pathFix)
        
        guard let url = resultUrl, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if let query = request.query, !query.isEmpty {
            components.queryItems = query.map(URLQueryItem.init)
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

}

extension HttpClient5 {
    public func websocket(path: String, maximumMessageSize: Int = 1_048_576) async throws -> WebSocketStream {
        
        var request = try await self.makeURLRequest(for: Request<String>(path: path))
        
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.scheme = (components.scheme ?? "http")
            .replacingOccurrences(of: "http", with: "ws")
            .replacingOccurrences(of: "https", with: "wss")
        
        request.url = components.url
        guard request.url != nil else {
            throw URLError(.badURL)
        }
        
        let socketConnection = self.session.webSocketTask(with: request)
        socketConnection.maximumMessageSize = maximumMessageSize
        let stream = WebSocketStream(task: socketConnection, encoder: self.encoder, uuid: self.uuid)
        return stream
    }
    
}


protocol OptionalDecoding {}

//struct AnyEncodable: Encodable {
//    let value: Encodable
//
//    func encode(to encoder: Encoder) throws {
//        try value.encode(to: encoder)
//    }
//}

extension OperationQueue {
    static func serial() -> OperationQueue {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }
}

extension Optional: OptionalDecoding {}

func encode(_ value: Encodable, using encoder: JSONEncoder) async throws -> Data? {
    if let data = value as? Data {
        return data
    } else if let string = value as? String {
        return string.data(using: .utf8)
    } else {
        return try await Task.detached {
            //TODO: why was this wrapped??? try encoder.encode(AnyEncodable(value: value))
            try encoder.encode(value)
        }.value
    }
}

func decode<T: Decodable>(_ data: Data, using decoder: JSONDecoder) async throws -> T {
    if data.isEmpty, T.self is OptionalDecoding.Type {
        return Optional<Decodable>.none as! T
    } else if T.self == Data.self {
        return data as! T
    } else if T.self == String.self {
        guard let string = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return string as! T
    } else {
        return try await Task.detached {
            try decoder.decode(T.self, from: data)
        }.value
    }
}

//TODO: throw someday more clear error on decode failure
// parse response body as a JSONobject
//do {
//    restResponse.result = try JSON.decoder.decode(T.self, from: data)
//    completionHandler(restResponse, nil)
//} catch DecodingError.dataCorrupted(let context) {
//    let keyPath = context.codingPath.map{$0.stringValue}.joined(separator: ".")
//    let values = "response JSON: dataCorrupted at \(keyPath): " + context.debugDescription
//    completionHandler(nil, RestError.deserialization(values: values))
//} catch DecodingError.keyNotFound(let key, _) {
//    let values = "response JSON: key not found for \(key.stringValue)"
//    completionHandler(nil, RestError.deserialization(values: values))
//} catch DecodingError.typeMismatch(_, let context) {
//    let keyPath = context.codingPath.map{$0.stringValue}.joined(separator: ".")
//    let values = "response JSON: type mismatch for \(keyPath): " + context.debugDescription
//    completionHandler(nil, RestError.deserialization(values: values))
//} catch DecodingError.valueNotFound(_, let context) {
//    let keyPath = context.codingPath.map{$0.stringValue}.joined(separator: ".")
//    let values = "response JSON: value not found for \(keyPath): " + context.debugDescription
//    completionHandler(nil, RestError.deserialization(values: values))
//} catch {
//    completionHandler(nil, RestError.deserialization(values: "response JSON: " + error.localizedDescription))
//}

