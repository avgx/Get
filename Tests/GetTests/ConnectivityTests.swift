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
        
        print(Connectivity.shared.ipv4 ?? "-")
    }
}
