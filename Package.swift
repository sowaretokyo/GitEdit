// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitEdit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GitEdit", targets: ["GitEdit"])
    ],
    targets: [
        .executableTarget(
            name: "GitEdit",
            path: "Sources/GitEdit"
        )
    ]
)
