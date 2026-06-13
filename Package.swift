// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitEdit",
    defaultLocalization: "ja",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GitEdit", targets: ["GitEdit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "GitEdit",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/GitEdit",
            exclude: ["Localization/README.md"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GitEditTests",
            dependencies: ["GitEdit"],
            path: "Tests/GitEditTests"
        )
    ]
)
