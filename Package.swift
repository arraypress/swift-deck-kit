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
