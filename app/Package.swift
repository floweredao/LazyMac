// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LazymacApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "lazymac", path: "Sources"),
    ]
)
