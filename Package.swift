// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeepWorkTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DeepWorkTimer", path: "Sources/DeepWorkTimer")
    ]
)
