// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MRWatcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MRWatcher",
            path: "Sources/MRWatcher"
        )
    ]
)
