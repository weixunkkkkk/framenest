// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FrameNest", platforms: [.macOS(.v14)], targets: [.executableTarget(name: "FrameNest", exclude: ["Resources"])])
