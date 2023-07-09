// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Evident",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13)
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
