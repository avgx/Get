//
//  NetworkMonitorTests.swift
//
//
//  Created by Alexey Govorovsky on 11.03.2024.
//

import XCTest
@testable import Get

import Foundation

final class ConnectivityTests: XCTestCase {
    override func setUp() async throws {
        
    }
    
    
    func test1() async throws {
        Connectivity.shared.startMonitoring()
        
        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 10)
        
        print(Connectivity.shared.isWifi())
        print(Connectivity.shared.isSatisfied())
        print(Connectivity.shared.ipv4 ?? "-")
    }
    
    func testScan() async throws {
        Connectivity.shared.startMonitoring()
        
        try await Task.sleep(nanoseconds: NSEC_PER_SEC / 10)
        
        guard Connectivity.shared.isWifi() else {
            XCTFail()
            return
        }
        guard Connectivity.shared.isSatisfied() else {
            XCTFail()
            return
        }
        guard let ip = Connectivity.shared.ipv4 else {
            XCTFail()
            return
        }
        
        let components = ip.split(separator: ".").map({ Int($0)! })
        XCTAssertTrue(components.count == 4)
        let my = components.last!
        let array = (2..<255).filter({ $0 != my })
        let list = array
            .map({ i in components.dropLast() + [i] })
            .map({ arr in arr.map({ String($0) }).joined(separator: ".") })
        print(list)
    }
}
