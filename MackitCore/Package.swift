// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MackitCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "MackitCore", targets: ["MackitCore"])],
    targets: [
        .target(name: "MackitCore", resources: [.copy("Shaders")]),
        .testTarget(name: "MackitCoreTests", dependencies: ["MackitCore"]),
    ]
)
