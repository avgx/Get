// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Get",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v10_15),
        .watchOS(.v6),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "Get", targets: ["Get"])
    ],
    dependencies: [
        .package(url: "https://github.com/avgx/Pulse.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4")
    ],
    targets: [
        .target(name: "Get", dependencies: [
            "Pulse",
            .product(name: "Logging", package: "swift-log")
        ]),
        .testTarget(name: "GetTests", dependencies: ["Get", "Pulse"])
    ]
)
