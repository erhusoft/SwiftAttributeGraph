// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftAttributeGraph",
    products: [
        .library(name: "SwiftAttributeGraph", targets: ["SwiftAttributeGraph"]),
        .executable(name: "UISimulator", targets: ["UISimulator"]),
    ],
    targets: [
        .target(name: "SwiftAttributeGraph"),
        .executableTarget(name: "UISimulator", dependencies: ["SwiftAttributeGraph"]),
        .testTarget(name: "SwiftAttributeGraphTests", dependencies: ["SwiftAttributeGraph"]),
    ]
)
