// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "check",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "check", targets: ["check"])
    ],
    targets: [
        .executableTarget(
            name: "check"
        ),
        .testTarget(
            name: "checkTests",
            dependencies: ["check"]
        )
    ]
)
