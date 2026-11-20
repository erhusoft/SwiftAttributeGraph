// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Bench",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "Bench",
            dependencies: [
                .product(name: "SwiftAttributeGraph", package: "sag_integration_worktree"),
            ],
            path: "Sources"
        ),
    ]
)
