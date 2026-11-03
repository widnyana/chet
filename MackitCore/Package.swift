// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MackitCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MackitCore", targets: ["MackitCore"]),
        .executable(name: "mackit-scan", targets: ["mackit-scan"]),
    ],
    targets: [
        .target(name: "MackitCore", resources: [.copy("Shaders")]),
        .executableTarget(name: "mackit-scan", dependencies: ["MackitCore"]),
        .testTarget(name: "MackitCoreTests", dependencies: ["MackitCore"]),
    ]
)
