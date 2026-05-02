import Foundation


/// HTTP-layer errors from validating a completed URL load
public enum HTTPError: Error, LocalizedError {
    /// Non-success status; `body` is the raw response payload (often JSON error from the server).
    case unacceptableStatusCode(statusCode: Int, body: Data, url: URL?)

    // TODO: localization for user-facing messages.
    public var errorDescription: String? {
        switch self {
        case .unacceptableStatusCode(let statusCode, let body, let url):
            let preview = String(data: body.prefix(2_048), encoding: .utf8) ?? "<\(body.count) bytes>"
            return "Response status code was unacceptable: \(statusCode). \n\(preview) \n\(String(describing: url?.absoluteString))"
        }
    }

    public var responseBody: Data {
        switch self {
        case .unacceptableStatusCode(_, let body, _):
            return body
        }
    }

    public var statusCodeIfUnacceptable: Int? {
        switch self {
        case .unacceptableStatusCode(let code, _, _):
            return code
        }
    }
}

extension HTTPError {
    /// Short message for UI or logging: UTF-8 JSON field `"error"` when present, otherwise ``HTTPURLResponse/localizedString(forStatusCode:)`` (unacceptable) or redirect description.
    ///
    /// For a full diagnostic string including URL and body preview, use ``LocalizedError/errorDescription``.
    public var compactFailureMessage: String {
        switch self {
        case .unacceptableStatusCode(let code, let body, _):
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let message = json["error"] as? String
            {
                return message
            }
            return HTTPURLResponse.localizedString(forStatusCode: code)
        }
    }
}
