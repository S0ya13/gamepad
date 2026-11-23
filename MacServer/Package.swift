// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacServer",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../SharedProtocol")],
    targets: [
        .executableTarget(
            name: "MacServer",
            dependencies: [.product(name: "SharedProtocol", package: "SharedProtocol")]
        ),
        .testTarget(name: "MacServerTests", dependencies: ["MacServer"]),
    ]
)
