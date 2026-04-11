// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibeWriteBackend",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.119.2")
    ],
    targets: [
        .executableTarget(
            name: "VibeWriteBackend",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "VibeWriteShared", package: "VibeWrite")
            ],
            path: "Sources/VibeWriteBackend"
        ),
        .testTarget(
            name: "VibeWriteBackendTests",
            dependencies: [
                "VibeWriteBackend",
                .product(name: "XCTVapor", package: "vapor"),
                .product(name: "VibeWriteShared", package: "VibeWrite")
            ],
            path: "Tests/VibeWriteBackendTests"
        )
    ]
)
