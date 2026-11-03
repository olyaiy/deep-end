// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DeepWorkTimer",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "DeepWorkTimer", path: "Sources/DeepWorkTimer"),
        // Small helper with Full Disk Access that switches Focus modes (see its main.swift).
        .executableTarget(name: "DeepWorkFocus", path: "Sources/DeepWorkFocus"),
    ]
)
