// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibeWrite",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VibeWriteShared",
            targets: ["VibeWriteShared"]
        ),
        .executable(
            name: "VibeWrite",
            targets: ["VibeWriteApp"]
        )
    ],
    targets: [
        .target(
            name: "VibeWriteShared",
            path: "Sources/VibeWriteShared"
        ),
        .executableTarget(
            name: "VibeWriteApp",
            dependencies: ["VibeWriteShared"],
            path: "Sources/VibeWriteApp"
        ),
        .testTarget(
            name: "VibeWriteAppTests",
            dependencies: ["VibeWriteApp", "VibeWriteShared"],
            path: "Tests/VibeWriteAppTests"
        )
    ]
)
