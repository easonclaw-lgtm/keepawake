// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SyncAgent",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SyncAgent",
            path: "Sources/SyncAgent"
        )
    ]
)
