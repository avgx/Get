import Foundation
import DebugThings
import RequestResponse
import EncodeDecode
import SSLPinning

/// HTTP transport with an owned ``URLSession`` and ``SessionDelegate``
public actor HTTPClient {
    public nonisolated let session: URLSession
    public nonisolated let sessionDelegate: SessionDelegate
    public nonisolated let interceptor: any RequestInterceptor
    nonisolated let validator: any ResponseValidator
    public nonisolated let observer: any RequestObserver
    public nonisolated let logger: any URLSessionTaskLogger
    public nonisolated let serverTrustPolicy: ServerTrustPolicy
    public nonisolated let redirectDisposition: RedirectDisposition
    public nonisolated let maxRetryAttempts: Int

    public init(
        configuration: URLSessionConfiguration = .ephemeral,
        redirectDisposition: RedirectDisposition = .follow,
        serverTrustPolicy: ServerTrustPolicy = .system,
        interceptor: RequestInterceptor = NoopRequestInterceptor(),
        validator: ResponseValidator = DefaultResponseValidator(),
        observer: RequestObserver = NoopRequestObserver(),
        logger: URLSessionTaskLogger = SimpleURLSessionTaskLogger(), //TODO: default to NoopURLSessionTaskLogger(),
        maxRetryAttempts: Int = 3
    ) {
        self.serverTrustPolicy = serverTrustPolicy
        self.redirectDisposition = redirectDisposition
        self.sessionDelegate = SessionDelegate(serverTrustPolicy: serverTrustPolicy, redirectDisposition: redirectDisposition, handler: nil, logger: logger)

        self.session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)
        self.interceptor = interceptor
        self.validator = validator
        self.observer = observer
        self.logger = logger
        self.maxRetryAttempts = max(1, maxRetryAttempts)
    }

    // MARK: Raw URLRequest

    public func data(for template: URLRequest) async throws -> (Data, URLResponse) {
        try await loadDataWithRetry(template: template)
    }

    // MARK: Request + RequestBuilder

    public func data<T: Sendable>(for request: Request<T>, with builder: RequestBuilder) async throws -> Response<Data> {
        let template = try await builder.urlRequest(for: request)
        guard template.url != nil else {
            throw URLError(.badURL)
        }
        let (data, response) = try await loadDataWithRetry(template: template)
        return Response(value: data, data: data, response: response)
    }

    private func loadDataWithRetry(template: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            var urlRequest = template
            urlRequest = try await interceptor.adapt(urlRequest)
            let start = Date()
            do {
                await observer.willSend(urlRequest)
                let (data, httpResponse) = try await session.dataTask(for: urlRequest)
                try validator.validate(data: data, response: httpResponse, request: urlRequest)
                await observer.didCompleteSuccess(urlRequest, response: httpResponse, body: data, duration: Date().timeIntervalSince(start))
                return (data, httpResponse)
            } catch {
                await observer.didCompleteFailure(urlRequest, error: error, duration: Date().timeIntervalSince(start))
                let shouldRetry = await interceptor.retry(template, dueTo: error)
                if shouldRetry, attempt < maxRetryAttempts {
                    continue
                }
                throw error
            }
        }
    }

    @discardableResult
    public func send<T: Decodable & Sendable>(_ request: Request<T>, with builder: RequestBuilder, decoder: JSONDecoder = JSONDecoder()) async throws -> Response<T> {
        let response = try await data(for: request, with: builder)
        do {
            let value: T = try await decodeBody(response.data, using: decoder)
            return response.map { _ in value }
        } catch {
            let template = try await builder.urlRequest(for: request)
            await observer.didDecodeFailure(
                template,
                response: response.response,
                body: response.data,
                expectedDecodableTypeName: String(describing: T.self),
                error: error
            )
            throw error
        }
    }

    @discardableResult
    public func send(_ request: Request<Void>, with builder: RequestBuilder) async throws -> Response<Void> {
        try await data(for: request, with: builder).map { _ in () }
    }
}
