// swift-tools-version: 6.1

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
        .library(name: "WS", targets: ["WS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/auth0/JWTDecode.swift", from: "4.0.0"),
        .package(url: "https://github.com/avgx/SSLPinning", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
        .package(url: "https://github.com/avgx/RequestResponse.git", from: "2.0.1"),
        .package(url: "https://github.com/avgx/EncodeDecode.git", from: "1.0.5"),
        .package(url: "https://github.com/avgx/DebugThings.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Get",
            dependencies: [
                "HTTP",
                "Multipart",
                "SSE",
                "WS",
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "EncodeDecode", package: "EncodeDecode"),
                .product(name: "SSLPinning", package: "SSLPinning"),
                .product(name: "DebugThings", package: "DebugThings"),
            ]
        ),
        .target(
            name: "HTTP",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "EncodeDecode", package: "EncodeDecode"),
                .product(name: "SSLPinning", package: "SSLPinning"),
                .product(name: "DebugThings", package: "DebugThings")
            ]
        ),
        .target(
            name: "Multipart",
            dependencies: [
                "HTTP",
                .product(name: "EncodeDecode", package: "EncodeDecode"),
            ]
        ),
        .target(
            name: "SSE",
            dependencies: [
                "HTTP",
                .product(name: "EncodeDecode", package: "EncodeDecode"),
            ]
        ),
        .target(
            name: "WS",
            dependencies: [
                "HTTP",
                .product(name: "DebugThings", package: "DebugThings"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SSLPinning", package: "SSLPinning")
            ]
        ),
        .testTarget(
            name: "HTTPTests",
            dependencies: [
                "HTTP",
                .product(name: "DebugThings", package: "DebugThings"),
                .product(name: "JWTDecode", package: "JWTDecode.swift"),
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "EncodeDecode", package: "EncodeDecode"),
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
                .product(name: "SSLPinning", package: "SSLPinning"),
            ],
            path: "Tests/HTTPLoggingTests"
        ),
        .testTarget(
            name: "MultipartTests",
            dependencies: [
                "Multipart",
                .product(name: "EncodeDecode", package: "EncodeDecode"),
            ],
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
                .product(name: "RequestResponse", package: "RequestResponse"),
                .product(name: "EncodeDecode", package: "EncodeDecode"),
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
