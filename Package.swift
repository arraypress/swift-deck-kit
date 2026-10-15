// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeckKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DeckKit", targets: ["DeckKit"])],
    dependencies: [
        // Strict reading: a key a design does not have is refused, by name.
        .package(url: "https://github.com/arraypress/swift-recipe-kit.git", from: "0.3.0"),
    ],
    targets: [
        .target(name: "DeckKit", dependencies: [.product(name: "RecipeKit", package: "swift-recipe-kit")],
                resources: [.process("Resources")]),
        .testTarget(name: "DeckKitTests", dependencies: ["DeckKit"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
