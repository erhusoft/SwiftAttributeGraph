// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ResumableGraphPrototype",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .target(name: "ResumableGraphPrototype"),
        .executableTarget(name: "ResumableGraphProfile", dependencies: ["ResumableGraphPrototype"]),
        .testTarget(name: "ResumableGraphPrototypeTests", dependencies: [
            "ResumableGraphPrototype",
            .product(name: "SwiftAttributeGraph", package: "SwiftAttributeGraph"),
        ]),
    ]
)
