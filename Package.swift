// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeepWorkTimer",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "DeepWorkTimer", path: "Sources/DeepWorkTimer")
    ]
)
