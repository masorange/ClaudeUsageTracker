// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "ClaudeUsageTracker",
            dependencies: ["UsageCore"]
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
