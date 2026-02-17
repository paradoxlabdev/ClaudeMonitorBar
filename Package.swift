// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeMonitorBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeMonitorBar",
            path: "Sources/ClaudeMonitorBar",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ClaudeMonitorBarTests",
            dependencies: ["ClaudeMonitorBar"],
            path: "Tests/ClaudeMonitorBarTests"
        ),
    ]
)
