import Foundation

extension HTTPURLResponse {
    public func normalizedHeaders() -> [String: String] {
        var h: [String: String] = [:]
        for (k, v) in allHeaderFields {
            guard let key = (k as? String)?.lowercased() else { continue }
            if let s = v as? String {
                h[key] = s.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let n = v as? NSNumber {
                h[key] = n.stringValue
            }
        }
        if h["content-type"] == nil, let mt = mimeType, !mt.isEmpty {
            h["content-type"] = mt
        }
        return h
    }
}
