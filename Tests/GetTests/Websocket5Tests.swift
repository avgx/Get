//
//  Websocket5Tests.swift
//
//
//  Created by Alexey Govorovsky on 11.03.2024.
//

import XCTest
@testable import Get

import Foundation



final class Websocket5Tests: XCTestCase {
    override func setUp() async throws {
        
    }
    
    /// wss://echo.websocket.org
    func test5() async throws {
        let http = HttpClient5(baseURL: URL(staticString: "https://echo.websocket.org"))
        let ws = try await http.websocket(path: "/")
        let start = Date()
        let expectation = expectation(description: "Wait for async function")
        
        Task {
            do {
                for try await message in ws {
                    // handle incoming messages
                    switch message {
                    case .data(let d):
                        let d50 = d.prefix(50)
                        let s = String(data: d50, encoding: .ascii) ?? "-"
                        print("data (\(d.count)) \(s)")
                    case .string(let s):
                        print("string \(Date().timeIntervalSince(start)) \(s)")
                        expectation.fulfill()
                    @unknown default:
                        fatalError()
                    }
                }
            } catch {
                // handle error
                print(error)
            }
        
            print("this will be printed once the stream ends")
        }
        
        let se = [ "hello", "world"]
        try await ws.send(se)
        
        await fulfillment(of: [expectation], timeout: TimeInterval(1))
//        try await Task.sleep(nanoseconds: NSEC_PER_SEC * 5) //5 sec
        try await ws.cancel()
        
    }
    
}
