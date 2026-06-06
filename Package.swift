// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaunchPad",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LaunchPad", targets: ["LaunchPad"]),
    ],
    targets: [
        .target(
            name: "LaunchPadProtocols",
            path: "Sources/LaunchPadProtocols"
        ),
        .target(
            name: "LaunchPad",
            dependencies: ["LaunchPadProtocols"],
            path: "Sources/LaunchPad",
            resources: [
                .process("../../Resources")
            ]
        ),
        .testTarget(
            name: "LaunchPadTests",
            dependencies: ["LaunchPad", "LaunchPadProtocols"],
            path: "Tests/LaunchPadTests"
        ),
    ]
)
