// swift-tools-version:6.0
//
// Windows-only stand-in for modelcontextprotocol/swift-sdk 0.12.1. The root
// manifest points at this folder only when building on Windows; every other
// platform keeps using the upstream package. See README.md for the patch.
//
// Only the `MCP` library is kept. Upstream's conformance executables (and
// with them swift-nio) and the Apple-only EventSource dependency are dropped.

import PackageDescription

let package = Package(
    name: "swift-sdk",
    products: [
        .library(name: "MCP", targets: ["MCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-system.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "MCP",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
