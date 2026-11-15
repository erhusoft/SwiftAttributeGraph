// swift-tools-version: 6.2
import PackageDescription

// Hand-written SwiftUI-compatible API and the experimental graph-backed semantic slice.
let package = Package(
    name: "ShellUI",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ShellUI", targets: ["ShellUI"])],
    dependencies: [.package(path: "..")],
    targets: [
        .target(name: "ShellUI", dependencies: [.product(name: "SwiftAttributeGraph", package: "SwiftAttributeGraph")]),
        // The same file is compiled against real SwiftUI by Scripts/check-compat.sh (without USE_SHELL).
        .target(name: "Samples", dependencies: ["ShellUI"], path: "Samples",
                swiftSettings: [.define("USE_SHELL")]),
        .testTarget(name: "ShellUITests", dependencies: ["ShellUI", "Samples", .product(name: "SwiftAttributeGraph", package: "SwiftAttributeGraph")]),
    ]
)
