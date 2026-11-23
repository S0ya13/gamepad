// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacServer",
    platforms: [.macOS(.v13)],
    products: [.library(name: "GamepadServerKit", targets: ["GamepadServerKit"])],
    dependencies: [.package(path: "../SharedProtocol")],
    targets: [
        // Shared by the command-line server and the menu bar app.
        .target(
            name: "GamepadServerKit",
            dependencies: [.product(name: "SharedProtocol", package: "SharedProtocol")]
        ),
        .executableTarget(name: "MacServer", dependencies: ["GamepadServerKit"]),
        .testTarget(name: "GamepadServerKitTests", dependencies: ["GamepadServerKit"]),
    ]
)
