import Foundation
import SSLPinning
import Testing
import WS

@Test func websocketDefaultConfigurationValues() {
    let c = WebSocket.Configuration.default
    #expect(c.maximumMessageSize == 16_777_216)
    #expect(c.connectionHandshakeTimeout == 30)
    #expect(c.logSentReceivedBytes == false)
    #expect(c.pingInterval == nil)
    #expect(c.readIdleTimeout == nil)
    if case .system = c.serverTrustPolicy {
    } else {
        Issue.record("expected serverTrustPolicy .system")
    }
    let session = c.makeSessionConfiguration()
    #expect(session.timeoutIntervalForRequest == c.timeoutIntervalForRequest)
    #expect(session.timeoutIntervalForResource == c.timeoutIntervalForResource)
}

@Test func websocketCheckedConfigurationEnablesPingAndReadIdle() {
    let c = WebSocket.Configuration.checked
    #expect(c.logSentReceivedBytes == true)
    #expect(c.pingInterval == 10)
    #expect(c.readIdleTimeout == 10)
    #expect(c.waitsForConnectivity == true)
}

@Test func websocketStateIdle() async {
    let url = URL(string: "wss://example.test/ws")!
    let request = URLRequest(url: url)
    let ws = WebSocket(request: request, configuration: .default)
    let state = await ws.connectionState()
    #expect(state == .idle)
}
