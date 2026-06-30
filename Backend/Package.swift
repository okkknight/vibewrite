// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibeWriteBackend",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.119.2"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "VibeWriteBackend",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "VibeWriteShared", package: "VibeWrite")
            ],
            path: "Sources/VibeWriteBackend"
        ),
        .testTarget(
            name: "VibeWriteBackendTests",
            dependencies: [
                "VibeWriteBackend",
                .product(name: "XCTVapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "VibeWriteShared", package: "VibeWrite")
            ],
            path: "Tests/VibeWriteBackendTests"
        )
    ]
)
