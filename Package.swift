// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Evident",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16)
    ],
    products: [
        .library(
            name: "Evident",
            targets: ["Evident"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "Evident",
            dependencies: []),
        .testTarget(
            name: "EvidentTests",
            dependencies: ["Evident"]),
    ]
)
