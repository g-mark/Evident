// swift-tools-version: 6.2

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
            targets: ["Evident"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Evident",
            dependencies: []
        ),
        .testTarget(
            name: "EvidentTests",
            dependencies: ["Evident"]
        )
    ]
)

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(contentsOf: [
        // Can't do this until Swift 6.3 is minimum (Xcode 26.4) _for clients_
        // See: https://github.com/swiftlang/swift-package-manager/issues/9517
        // .treatAllWarnings(as: .error),
        .defaultIsolation(nil),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances")
    ])
    target.swiftSettings = settings
}
