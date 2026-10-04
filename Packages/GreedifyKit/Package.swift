// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GreedifyKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GreedifyKit", targets: ["GreedifyKit"]),
    ],
    targets: [
        .target(name: "GreedifyKit", resources: [.process("Theme/Builtin")]),
        // Developer tool: drafts a curated theme from a Winamp skin (docs/adding-a-skin.md).
        .executableTarget(name: "skin-recipe", dependencies: ["GreedifyKit"]),
        .testTarget(name: "GreedifyKitTests", dependencies: ["GreedifyKit"]),
    ]
)
