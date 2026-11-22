// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftAttributeGraph",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftAttributeGraph", targets: ["SwiftAttributeGraph"]),
    ],
    targets: [
        .target(name: "SwiftAttributeGraph"),
        .testTarget(name: "SwiftAttributeGraphTests", dependencies: ["SwiftAttributeGraph"]),
    ]
)
