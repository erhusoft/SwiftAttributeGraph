// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftAttributeGraph",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftAttributeGraph", targets: ["SwiftAttributeGraph"]),
        .executable(name: "UISimulator", targets: ["UISimulator"]),
        .executable(name: "StressBenchmark", targets: ["StressBenchmark"]),
    ],
    targets: [
        .target(name: "SwiftAttributeGraph"),
        .executableTarget(name: "UISimulator", dependencies: ["SwiftAttributeGraph"]),
        .executableTarget(name: "StressBenchmark", dependencies: ["SwiftAttributeGraph"]),
        .testTarget(name: "SwiftAttributeGraphTests", dependencies: ["SwiftAttributeGraph"]),
    ]
)
