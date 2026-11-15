// swift-tools-version: 6.2
import PackageDescription

// The SwiftUI-compatible API as hand-written shells (docs/DISENO-API-SWIFTUI.md). Independent of the engine package for now.
let package = Package(
    name: "ShellUI",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ShellUI", targets: ["ShellUI"])],
    targets: [
        .target(name: "ShellUI"),
        // The same file is compiled against real SwiftUI by Scripts/check-compat.sh (without USE_SHELL).
        .target(name: "Samples", dependencies: ["ShellUI"], path: "Samples",
                swiftSettings: [.define("USE_SHELL")]),
        .testTarget(name: "ShellUITests", dependencies: ["ShellUI", "Samples"]),
    ]
)
