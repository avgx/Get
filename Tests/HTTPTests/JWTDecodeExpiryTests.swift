import Foundation
import JWTDecode
import Testing

@Test func jwtExpParsesFromUnsignedPayload() throws {
    // HS256 header + payload {"exp":1700000000} (signature not verified by JWTDecode)
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MDAwMDAwMDB9.xx"
    let decoded = try decode(jwt: jwt)
    #expect(decoded.expiresAt == Date(timeIntervalSince1970: 1_700_000_000))
}
