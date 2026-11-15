// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MiniUIApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "MiniUIAppCore",
            dependencies: [
                .product(name: "SwiftAttributeGraph", package: "SwiftAttributeGraph"),
            ]
        ),
        .executableTarget(
            name: "MiniUIApp",
            dependencies: ["MiniUIAppCore"]
        ),
        .testTarget(
            name: "MiniUIAppTests",
            dependencies: ["MiniUIAppCore"]
        ),
    ]
)
