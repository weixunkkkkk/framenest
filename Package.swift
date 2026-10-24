// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FrameNest",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FrameNestCore"),
        .executableTarget(name: "FrameNest", dependencies: ["FrameNestCore"], exclude: ["Resources"]),
        .executableTarget(name: "FrameNestMCP", dependencies: ["FrameNestCore"])
    ]
)
