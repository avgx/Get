// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Get",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "Get", targets: ["Get"]),
        .library(name: "HTTP", targets: ["HTTP"]),
        .library(name: "Multipart", targets: ["Multipart"]),
        .library(name: "SSE", targets: ["SSE"]),
        .library(name: "Auth", targets: ["Auth"]),
        .library(name: "WS", targets: ["WS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/auth0/JWTDecode.swift", from: "4.0.0"),
        .package(url: "https://github.com/avgx/SSLPinning", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
        .package(url: "https://github.com/avgx/RequestResponse.git", from: "1.0.0"),
        .package(url: "https://github.com/avgx/DebugThings.git", branch: "main")
    ],
    targets: [
        .target(
            name: "Get",
            dependencies: [
                "HTTP",
                "Multipart",
                "SSE",
                "Auth",
                "WS",
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "SSLPinning", package: "SSLPinning"),
                .product(name: "DebugThings", package: "DebugThings"),
            ],
            exclude: ["README.md"]
        ),
        .target(
            name: "HTTP",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "SSLPinning", package: "SSLPinning"),
                .product(name: "DebugThings", package: "DebugThings")
            ],
            exclude: ["README.md"]
        ),
        .target(
            name: "Multipart",
            dependencies: ["HTTP"],
            exclude: ["README.md"]
        ),
        .target(
            name: "SSE",
            dependencies: ["HTTP"],
            exclude: ["README.md"]
        ),
        .target(
            name: "Auth",
            dependencies: ["HTTP"],
            exclude: ["README.md"]
        ),
        .target(
            name: "WS",
            dependencies: [
                "HTTP",
                .product(name: "DebugThings", package: "DebugThings"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SSLPinning", package: "SSLPinning")
            ],
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "HTTPTests",
            dependencies: [
                "HTTP",
                "Auth",
                .product(name: "DebugThings", package: "DebugThings"),
                .product(name: "JWTDecode", package: "JWTDecode.swift"),
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "SSLPinning", package: "SSLPinning"),
            ],
            path: "Tests/HTTPTests"
        ),
        .testTarget(
            name: "HTTPLoggingTests",
            dependencies: [
                "HTTP",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "DebugThings", package: "DebugThings"),
                .product(name: "DebugThingsPulseProxy", package: "DebugThings"),
                .product(name: "SSLPinning", package: "SSLPinning"),
            ],
            path: "Tests/HTTPLoggingTests"
        ),
        .testTarget(
            name: "MultipartTests",
            dependencies: ["Multipart"],
            path: "Tests/MultipartTests"
        ),
        .testTarget(
            name: "SSETests",
            dependencies: ["SSE"],
            path: "Tests/SSETests"
        ),
        .testTarget(
            name: "LANIntegrationTests",
            dependencies: [
                "HTTP",
                "Multipart",
                "SSE",
                "WS",
                "Auth",
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "DebugThings", package: "DebugThings"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SSLPinning", package: "SSLPinning"),
            ],
            path: "Tests/LANIntegrationTests"
        ),
        .testTarget(
            name: "WSTests",
            dependencies: [
                "WS",
                .product(name: "SSLPinning", package: "SSLPinning"),
            ],
            path: "Tests/WSTests"
        ),
    ]
)
