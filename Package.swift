// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Adhan",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_13),
        .tvOS(.v12),
        .watchOS(.v6),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Adhan",
            targets: ["Adhan"]
        )
    ],
    targets: [
        .target(
            name: "Adhan",
            path: "Sources",
            resources: [.copy("Resources/LondonPrayerTimes.json")]
        ),
        .testTarget(
            name: "Tests",
            dependencies: ["Adhan"],
            path: "Tests",
            resources: [.copy("Resources")]
        ),
    ]
)
