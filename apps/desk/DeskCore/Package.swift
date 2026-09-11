// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DeskCore", targets: ["DeskCore"])],
    targets: [
        .target(name: "DeskCore"),
        .testTarget(name: "DeskCoreTests", dependencies: ["DeskCore"]),
    ]
)
