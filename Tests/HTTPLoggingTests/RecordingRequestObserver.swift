import Foundation
import HTTP

actor RecordingRequestObserver: RequestObserver {
    private var send = 0
    private var success = 0
    private var failure = 0
    private var decodeFailure = 0

    func counts() -> (send: Int, success: Int, failure: Int, decodeFailure: Int) {
        (send, success, failure, decodeFailure)
    }

    func willSend(_ request: URLRequest) async {
        send += 1
    }

    func didCompleteSuccess(_ request: URLRequest, response: URLResponse, body: Data, duration: TimeInterval) async {
        success += 1
    }

    func didCompleteFailure(_ request: URLRequest, error: Error, duration: TimeInterval) async {
        failure += 1
    }

    func didDecodeFailure(
        _ request: URLRequest,
        response: URLResponse,
        body: Data,
        expectedDecodableTypeName: String,
        error: Error
    ) async {
        decodeFailure += 1
    }
}
