import Foundation
import EncodeDecode
import RequestResponse

extension HTTPClient {
    public func pages<T: Decodable & Sendable>(
        _ request: Request<PagedResponse<T>>,
        with builder: RequestBuilder,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> [T] {
        let res = try await data(for: request, with: builder)
        let ct = (res.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type") ?? ""

        if ct.hasPrefix("text/event-stream") {
            return try decodeSse(T.self, from: res.data, using: decoder)
        }
        if isMultipartRelated(ct) {
            return try decodeMultipartRelated(T.self, contentType: ct, from: res.data, using: decoder)
        }
        throw URLError(.cannotDecodeContentData)
    }
}
