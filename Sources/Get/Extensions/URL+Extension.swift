import Foundation

extension URL {
    public init(staticString string: StaticString) {
        guard let url = URL(string: "\(string)") else {
            preconditionFailure("Invalid static URL string: \(string)")
        }
        
        self = url
    }
}

extension URL {
    public func pretty() -> String {
        guard var builder = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self.absoluteString
        }
        
        builder.scheme = nil
        
        guard let url1 = builder.url else {
            return self.absoluteString
        }
        let srv = url1.hasDirectoryPath ? url1 : url1.appendingPathComponent("/")
        return String(srv.absoluteString.dropFirst(2).dropLast())
    }
    
    public var isHttps: Bool {
        return self.absoluteString.starts(with: "https://")
    }
}
