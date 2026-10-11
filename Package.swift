// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeckKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DeckKit", targets: ["DeckKit"])],
    targets: [
        .target(name: "DeckKit", resources: [.process("Resources")]),
        .testTarget(name: "DeckKitTests", dependencies: ["DeckKit"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
