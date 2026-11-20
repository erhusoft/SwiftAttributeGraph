// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NativeGraphProbe",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "SwiftAttributeGraph", path: "..")],
    targets: [.executableTarget(name: "Probe", dependencies: [
        .product(name: "SwiftAttributeGraph", package: "SwiftAttributeGraph")
    ])]
)
