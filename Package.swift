// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snipkin",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Snipkin", targets: ["Snipkin"])],
    targets: [
        .target(name: "SnipkinCore"),
        .executableTarget(name: "Snipkin", dependencies: ["SnipkinCore"], resources: [.copy("Resources")]),
        .testTarget(name: "SnipkinCoreTests", dependencies: ["SnipkinCore"])
    ],
    swiftLanguageModes: [.v5]
)
