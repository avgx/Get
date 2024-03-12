//
//  IPMonitor.swift
//
//  https://stackoverflow.com/questions/30748480/swift-get-devices-wifi-ip-address/65202648#65202648

import Foundation
import Network


extension Notification.Name {
    public static let connectivityStatus = Notification.Name(rawValue: "ConnectivityStatusChanged")
}

extension NWInterface.InterfaceType: CaseIterable {
    public static var allCases: [NWInterface.InterfaceType] = [
        .other,
        .wifi,
        .cellular,
        .loopback,
        .wiredEthernet
    ]
}

final class Connectivity {
    static let shared = Connectivity()

    private let queue = DispatchQueue(label: "NetworkMonitor")
    private let monitor: NWPathMonitor

    public private(set) var isReady: Bool?
    public private(set) var ipv4: String?
    
    private init() {
        monitor = NWPathMonitor()
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] (path: NWPath) in
            self?.isReady = true
            self?.ipv4 = path.availableInterfaces.first?.ipv4
            
            NotificationCenter.default.post(name: .connectivityStatus, object: nil)
        }
        monitor.start(queue: queue)
    }

    func stopMonitoring() {
        monitor.cancel()
    }
}

extension Connectivity {
    func activeInterfaceType() -> NWInterface.InterfaceType? {
        let path = monitor.currentPath
        return path.availableInterfaces.filter {
            path.usesInterfaceType($0.type)
        }.first?.type
    }
    
    public func isWifi() -> Bool {
        return activeInterfaceType() == .wifi
    }
    
    public func isSatisfied() -> Bool {
        let path = monitor.currentPath
        return path.isSatisfied()
    }
}

extension NWPath {
    func isSatisfied() -> Bool {
        if case .satisfied = status { return true }
        return false
    }
}

extension NWInterface {
    func address(family: Int32) -> String? {
        var address: String?

        // get list of all interfaces on the local machine:
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }

        // for each interface ...
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(family) {
                // Check interface name:
                if name == String(cString: interface.ifa_name) {
                    // Convert interface address to a human readable string:
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)

        return address
    }

    var ipv4: String? { address(family: AF_INET) }
    var ipv6: String? { address(family: AF_INET6) }
}
