import XCTest
@testable import Get

import Foundation
import Pulse

final class StreamTests: XCTestCase {
    override func setUp() async throws {
        Task {
            LoggerStore.shared.removeAll()
        }
    }
    
    func testStream() async throws {
        let expectation = expectation(description: "Wait for async function")
        var frames: [Data] = []
        let url = URL(string: "http://136.243.144.109:8000/asip-api/live/media/DEMOSERVER/DeviceIpint.1/SourceEndpoint.video:0:0?format=mp4&id=1234567890")!
        let request = URLRequest(url: url)
        
        
        let received: (Data) -> () = { data in
            print("received \(data.count)")
            frames.append(data)
            if frames.count == 100 {
                expectation.fulfill()
            }
        }
        
        let delegate = DataStreamDelegate(loggerConfiguration: .sensitive, received: received)
        
        let configuration = URLSessionConfiguration.custom
        configuration.httpAdditionalHeaders = [
            "Authorization": Authorization.basic(.init(user: "root", password: "root")).header!,
        ]
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let dataTask = session.dataTask(with: request)
        
        
        dataTask.resume()
        
        await fulfillment(of: [expectation], timeout: TimeInterval(20))
        
        dataTask.cancel()
        session.finishTasksAndInvalidate()
        
//        try await Task.sleep(nanoseconds: NSEC_PER_SEC)
//        try await LoggerStore.shared.export(to: URL(string: "file:///Users/avgx/tmp/1.pulse")!)
//        try await Task.sleep(nanoseconds: NSEC_PER_SEC)
        
        XCTAssert(frames.count >= 100)
        
    }
}
