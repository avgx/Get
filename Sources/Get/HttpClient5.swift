import DebugThings
import Foundation
import HTTP
import RequestResponse

private struct NoopURLSessionTaskLogger: URLSessionTaskLogger, Sendable {
    func logTaskCreated(_: URLSessionTask) {}
    func logTask(_: URLSessionTask, didCompleteWithError _: Error?) {}
    func logTask(_: URLSessionTask, didFinishCollecting _: URLSessionTaskMetrics) {}
    func logTask(_: URLSessionTask, didFinishDecodingWithError _: Error?) {}
    func logDataTask(_: URLSessionDataTask, didReceive _: Data) {}
}

/// Compatibility façade over ``HTTPClient`` and ``RequestBuilder`` for callers migrating from the legacy monolithic ``Get`` module.
public actor HttpClient5 {
    public nonisolated let authorization: Authorization
    public nonisolated let baseURL: URL
    public nonisolated let session: URLSession

    private let client: HTTPClient
    private let builder: RequestBuilder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        authorization: Authorization = .insecure,
        sessionConfiguration: URLSessionConfiguration = .custom,
        loggerConfiguration: LoggerConfiguration = .sensitive,
        encoder: JSONEncoder = .custom,
        decoder: JSONDecoder = .custom,
        ssl: SSL = .system
    ) {
        self.authorization = authorization
        self.baseURL = baseURL
        self.decoder = decoder

        let configuration = sessionConfiguration
        if let authHeader = authorization.header {
            configuration.httpAdditionalHeaders = [
                "Authorization": authHeader,
                "Accept-Encoding": "gzip, deflate, identity",
                "Accept-Language": String(Locale.current.identifier.prefix(2)),
            ]
        }

        let logger = Self.makeLogger(configuration: loggerConfiguration)
        let httpClient = HTTPClient(
            configuration: configuration,
            serverTrustPolicy: ssl.asServerTrustPolicy(),
            logger: logger
        )
        self.client = httpClient
        self.session = httpClient.session

        let sessionHeaders = Self.stringHeaders(from: configuration.httpAdditionalHeaders)
        self.builder = RequestBuilder(baseURL: baseURL, encoder: encoder, sessionDefaultHeaders: sessionHeaders)
    }

    public func finishTasksAndInvalidate() {
        session.finishTasksAndInvalidate()
    }

    @discardableResult
    public func send<T: Decodable & Sendable>(_ request: Request<T>) async throws -> Response<T> {
        try await client.send(request, with: builder, decoder: decoder)
    }

    @discardableResult
    public func send(_ request: Request<String>) async throws -> Response<String> {
        let response = try await client.data(for: request, with: builder)
        guard let value = String(data: response.data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return response.map { _ in value }
    }

    @discardableResult
    public func send(_ request: Request<Void>) async throws -> Response<Void> {
        try await client.send(request, with: builder)
    }

    public func data<T: Sendable>(for request: Request<T>) async throws -> Response<Data> {
        try await client.data(for: request, with: builder)
    }

    public func makeURLRequest<T>(for request: Request<T>) async throws -> URLRequest {
        try await builder.urlRequest(for: request)
    }

    private nonisolated static func makeLogger(configuration: LoggerConfiguration) -> any URLSessionTaskLogger {
        switch configuration {
        case .none:
            return NoopURLSessionTaskLogger()
        case .sensitive:
            return SimpleURLSessionTaskLogger(label: "network", logReceiveData: false)
        case .full:
            return SimpleURLSessionTaskLogger(label: "network", logReceiveData: true)
        }
    }

    private nonisolated static func stringHeaders(from raw: [AnyHashable: Any]?) -> [String: String]? {
        guard let raw, !raw.isEmpty else { return nil }
        var out: [String: String] = [:]
        for (key, value) in raw {
            guard let ks = key as? String, let vs = value as? String else { continue }
            out[ks] = vs
        }
        return out.isEmpty ? nil : out
    }
}
