// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoLinter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VideoLinter",
            path: "Sources/VideoLinter"
        )
    ]
)
