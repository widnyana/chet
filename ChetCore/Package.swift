// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChetCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ChetCore", targets: ["ChetCore"]),
        .executable(name: "chet-scan", targets: ["chet-scan"]),
    ],
    targets: [
        .target(name: "ChetCore", resources: [.copy("Shaders")]),
        .executableTarget(name: "chet-scan", dependencies: ["ChetCore"]),
        .testTarget(name: "ChetCoreTests", dependencies: ["ChetCore"]),
    ]
)
