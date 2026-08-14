// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MRWatcher",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            .upToNextMinor(from: "2.9.5")
        )
    ],
    targets: [
        .executableTarget(
            name: "MRWatcher",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MRWatcher"
        )
    ]
)
