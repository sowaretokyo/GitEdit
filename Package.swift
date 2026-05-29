// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitCode",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GitCode", targets: ["GitCode"])
    ],
    targets: [
        .executableTarget(
            name: "GitCode",
            path: "Sources/GitCode"
        )
    ]
)
