import Foundation
import EncodeDecode
import RequestResponse

extension HTTPClient {
    /// Decodes a buffered paged stream (`text/event-stream` or `multipart/related`) into decoded page values.
    ///
    /// Use this instead of ``send(_:with:decoder:)`` for ``Request`` values whose response type is ``PagedResponse``.
    public func pages<T: Decodable & Sendable>(
        _ request: Request<PagedResponse<T>>,
        with builder: RequestBuilder,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> [T] {
        let res = try await data(for: request, with: builder)
        let contentType = (res.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type") ?? ""
        return try Self.decodePagedBody(T.self, contentType: contentType, from: res.data, using: decoder)
    }

    @available(*, unavailable, message: "Use pages(_:with:decoder:) for paged stream endpoints.")
    public func send<T: Decodable & Sendable>(
        _ request: Request<PagedResponse<T>>,
        with builder: RequestBuilder,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Response<PagedResponse<T>> {
        fatalError()
    }

    static func decodePagedBody<T: Decodable & Sendable>(
        _ type: T.Type,
        contentType: String,
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> [T] {
        let mediaType = contentType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if mediaType == "text/event-stream" {
            return try decodeSse(type, from: data, using: decoder)
        }
        if isMultipartRelated(contentType) {
            return try decodeMultipartRelated(type, contentType: contentType, from: data, using: decoder)
        }
        throw URLError(.cannotDecodeContentData)
    }
}
