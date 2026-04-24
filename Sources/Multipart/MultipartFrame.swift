import Foundation

/// One body part from a `multipart/x-mixed-replace` or `multipart/related` HTTP entity.
public struct MultipartFrame: Sendable {
    /// Part header field names are lowercased; values are trimmed.
    public let headers: [String: String]
    public let body: Data

    public init(headers: [String: String], body: Data) {
        self.headers = headers
        self.body = body
    }

    /// Media type of the part from the `Content-Type` header (type/subtype only, no parameters).
    public var mimeType: String? {
        guard let ct = headers["content-type"] else { return nil }
        let trimmed = ct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let semi = trimmed.firstIndex(of: ";") else {
            return trimmed.isEmpty ? nil : trimmed
        }
        return String(trimmed[..<semi]).trimmingCharacters(in: .whitespaces)
    }
}

extension MultipartFrame: CustomStringConvertible {
    public var description: String {
        "\(mimeType ?? "unknown") headers=\(headers.keys.sorted()) body=\(body.count)"
    }
}
