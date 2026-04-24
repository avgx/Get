import Foundation

public protocol ResponseValidator: Sendable {
    func validate(data: Data, response: URLResponse, request: URLRequest) throws
}

public struct DefaultResponseValidator: ResponseValidator {
    public init() {}
    
    public func validate(
        data: Data,
        response: URLResponse,
        request: URLRequest
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        let code = http.statusCode
        
        if (200..<300).contains(code) {
            return
        }
        
        //        if (300..<400).contains(code),
        //           let location = http.value(forHTTPHeaderField: "Location"),
        //           let url = URL(string: location) {
        //            throw HTTPError.redirectTo(url)
        //        }
        
        throw HTTPError.unacceptableStatusCode(
            statusCode: code,
            body: data,
            url: response.url ?? request.url!
        )
    }
}

public struct RequireStatus200: ResponseValidator {
    public init() {}
    
    public func validate(
        data: Data,
        response: URLResponse,
        request: URLRequest
    ) throws {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw HTTPError.unacceptableStatusCode(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                body: data,
                url: request.url!
            )
        }
    }
}

public struct RequireContentType: ResponseValidator {
    private let expected: String
    
    public init(_ expected: String) {
        self.expected = expected
    }
    
    public func validate(
        data: Data,
        response: URLResponse,
        request: URLRequest
    ) throws {
        guard let http = response as? HTTPURLResponse,
              let ct = http.value(forHTTPHeaderField: "Content-Type"),
              ct.lowercased().contains(expected.lowercased()) else {
            throw URLError(.cannotParseResponse)
        }
    }
}

