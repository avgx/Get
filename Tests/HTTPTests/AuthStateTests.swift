import Auth
import Foundation
import Testing

@Test func authStateRefreshCoalesces() async throws {
    let state = AuthState(refresh: {
        //try await Task.sleep(for: .milliseconds(100))
        try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 100)
        return "one-token"
    })
    let background = Task { try await state.refresh() }
    try await Task.sleep(nanoseconds: NSEC_PER_MSEC * 10)
    let fromSecond = try await state.refresh()
    let fromFirst = try await background.value
    #expect(fromFirst == "one-token")
    #expect(fromSecond == "one-token")
}

@Test func proactiveMarginRefreshesBeforeExpiry() async throws {
    let state = AuthState(
        policy: RefreshPolicy(margin: 120),
        refresh: { "new-token" }
    )
    let soon = Date().addingTimeInterval(60)
    await state.setTokens(access: "old", refresh: "r", accessExpiresAt: soon)
    let token = try await state.validAccessToken()
    #expect(token == "new-token")
}
