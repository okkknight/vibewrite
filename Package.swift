// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibeWrite",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VibeWrite",
            targets: ["VibeWriteApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VibeWriteApp",
            path: "Sources/VibeWriteApp"
        ),
        .testTarget(
            name: "VibeWriteAppTests",
            dependencies: ["VibeWriteApp"],
            path: "Tests/VibeWriteAppTests"
        )
    ]
)
