// swift-tools-version: 5.9
// Minimal iOS test project for validating dev-desk new-project bootstrap flow

import PackageDescription

let package = Package(
    name: "iOSNewTestProject",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "iOSNewTestProject",
            targets: ["iOSNewTestProject"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "iOSNewTestProject",
            dependencies: []
        ),
        .testTarget(
            name: "iOSNewTestProjectTests",
            dependencies: ["iOSNewTestProject"]
        )
    ]
)
