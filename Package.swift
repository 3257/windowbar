// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WindowBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WindowBar", targets: ["WindowBar"])],
    targets: [
        .target(name: "WindowBarCore"),
        .executableTarget(name: "WindowBar", dependencies: ["WindowBarCore"]),
        .testTarget(name: "WindowBarCoreTests", dependencies: ["WindowBarCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
