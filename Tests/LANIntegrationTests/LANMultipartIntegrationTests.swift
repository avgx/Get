import Foundation
import DebugThings
import HTTP
import Multipart
import SSLPinning
import Testing

// MARK: - Multipart / MJPEG (HTTPClient.frames)

/// Requires `GET_TEST_MJPEG_PATH` and URLSession per-part multipart. First JPEG ``MultipartFrame`` body from ``HTTPClient/frames``.
@Test(.tags(.integration))
func lanMultipartFramesFirstJpegPart() async throws {
    guard let path = TestEnvironment.value(for: "GET_TEST_MJPEG_PATH"), !path.isEmpty else {
        return
    }
    guard let request = LANIntegration.basicAuthorizedGET(path: path) else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.mjpeg.frames")
    let client = HTTPClient(configuration: .ephemeral, serverTrustPolicy: .system, logger: taskLog)
    let stream = await client.frames(request: request)
    let part = try await LANIntegration.firstValue(in: stream)
    #expect(part != nil, "No multipart frame within timeout (check GET_TEST_MJPEG_PATH and multipart Content-Type).")
    guard let part else { return }
    #expect(part.body.count >= 2)
    #expect(Array(part.body.prefix(2)) == [0xFF, 0xD8])
}

/// Requires `GET_TEST_MJPEG_PATH` and multipart. Collects at least three ``MultipartFrame`` values.
@Test(.tags(.integration))
func lanMultipartFramesCollectThree() async throws {
    guard let path = TestEnvironment.value(for: "GET_TEST_MJPEG_PATH"), !path.isEmpty else {
        return
    }
    guard let request = LANIntegration.basicAuthorizedGET(path: path) else {
        return
    }
    DebugThingsTestSupport.installStandardOutputLogging()
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.mjpeg.frames.probe")
    let client = HTTPClient(configuration: .ephemeral, serverTrustPolicy: .system, logger: taskLog)
    let stream = await client.frames(request: request)
    let frames = try await LANIntegration.collectAtLeastThrowing(
        minimumCount: 3,
        from: stream,
        timeoutNanoseconds: 25_000_000_000
    )
    #expect(frames.count >= 3, "Expected ≥3 multipart frames (check GET_TEST_MJPEG_PATH and multipart Content-Type).")
    for frame in frames.prefix(3) {
        #expect(frame.body.count >= 2)
        #expect(Array(frame.body.prefix(2)) == [0xFF, 0xD8])
    }
}

@Test(.tags(.integration), .disabled("Manual arc.play multipart probe; not for CI."))
func lanMultipartArcPlaySecureVideoCollectThree() async throws {
    let url = URL(
        string: "http://172.19.2.106:8085/web2/secure/video/action.do?command=arc.play&version=4.10.0.0&video_in=CAM:1&time_from=2026-04-23T16:32:42.000%2B03:00&height=576&fps=10.0&speed_factor=1.0&normalize=true&sessionid=4CD473FE-3D72-4CAD-876D-82BD256CA52B"
    )!
    //http://172.19.2.106:8085/web2/secure/video/action.do?xcommand=live.play&version=4.10.0.0&video_in=CAM:4&height=576&normalize=true&fps=10.0&sessionid=8320B59C-5C95-4962-9FD7-A6001497E759
    var request = URLRequest(url: url)
    let token = Data("1:1".utf8).base64EncodedString()
    request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    
    DebugThingsTestSupport.installStandardOutputLogging()
    let taskLog = SimpleURLSessionTaskLogger(label: "lan.arcplay.frames.probe")
    let client = HTTPClient(configuration: .ephemeral, serverTrustPolicy: .system, logger: taskLog)
    
    var i = 0
    for try await item in await client.frames(request: request) {
        print("frame cameraid:\(item.headers["x-cameraid"]) time:\(item.headers["x-time"]) timestamp:\(item.headers["x-timestamp"]) \(item.headers["x-height"])p \(item.description)")
        i += 1
        if i >= 10 {
            break
        }
    }
    
    try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
    
    let stream = await client.frames(request: request)
    
    
    let frames = try await LANIntegration.collectAtLeastThrowing(
        minimumCount: 3,
        from: stream,
        timeoutNanoseconds: 25_000_000_000
    )
    #expect(frames.count >= 3, "Expected ≥3 multipart frames.")
    for frame in frames.prefix(3) {
        #expect(frame.body.count >= 2)
        #expect(Array(frame.body.prefix(2)) == [0xFF, 0xD8])
    }
}
