import Foundation
import HTTP
import RequestResponse
import SSLPinning
import Testing

/// Maps a failing `URLSession` TLS error into ``SSLPinningError/systemTrustFailed`` and throws it (for apps that surface one error type).
@Test func selfSignedBadSSL_throwMappedSystemTrustFailed() async throws {
    await #expect(throws: SSLPinningError.self) {
        try await throwMappedSelfSignedBadSSL()
    }
}

// TODO: surface an error that includes optional user-pinning certificate metadata, not only a generic failure.
/// Performs one request, maps the URL error to ``SSLPinningError``, asserts on ``URLError.Code``, then rethrows for `#expect(throws:)`.
private func throwMappedSelfSignedBadSSL() async throws {
    let url = URL(string: "https://self-signed.badssl.com/")!

    let configuration = URLSessionConfiguration.ephemeral
    let client = HTTPClient(configuration: configuration)
    let builder = RequestBuilder.json(
        baseURL: url,
        encoder: JSONEncoder()
    )
    let req = Request<String>(path: "/product/version", method: .get)

    let ssl: SSLPinningError
    do {
        _ = try await client.send(req, with: builder)
        Issue.record("Expected TLS failure from self-signed.badssl.com")
        throw URLError(.unknown)
    } catch let probeError {
        guard let mapped = SSLPinningError.systemTrustFailureIfPresent(in: probeError) else {
            Issue.record("Expected an SSL certificate URL error, got \(probeError)")
            throw probeError
        }
        ssl = mapped
    }

    guard case .systemTrustFailed(let urlError) = ssl else {
        Issue.record("Expected systemTrustFailed, got \(ssl)")
        throw ssl
    }

    let acceptableCodes: [URLError.Code] = [
        .serverCertificateUntrusted,
        .secureConnectionFailed,
        .serverCertificateHasUnknownRoot
    ]
    #expect(acceptableCodes.contains(urlError.code))

    #expect((ssl.errorDescription ?? "").isEmpty == false)
    #expect((ssl.failureReason ?? "").isEmpty == false)
    #expect((ssl.recoverySuggestion ?? "").isEmpty == false)
    #expect(ssl.failureReason?.contains(urlError.localizedDescription) == true)

    throw ssl
}
