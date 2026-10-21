// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanMac",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CleanerCore", targets: ["CleanerCore"]), .executable(name: "Clair", targets: ["Clair"])],
    targets: [
        .target(name: "CleanerCore"),
        .executableTarget(name: "Clair", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"])
    ]
)
