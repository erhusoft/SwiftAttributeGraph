// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MiniUIApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "MiniUIApp",
            dependencies: [
                .product(name: "SwiftAttributeGraph", package: "SwiftAttributeGraph"),
            ]
        ),
    ]
)
