// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Probe",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(name: "Adhan", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Probe",
            dependencies: [.product(name: "Adhan", package: "Adhan")],
            path: "Sources"
        )
    ]
)
