// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ResumableGraphPrototype",
    dependencies: [.package(path: "../..")],
    targets: [
        .target(name: "ResumableGraphPrototype"),
        .testTarget(name: "ResumableGraphPrototypeTests", dependencies: [
            "ResumableGraphPrototype",
            .product(name: "SwiftAttributeGraph", package: "SwiftAttributeGraph"),
        ]),
    ]
)
