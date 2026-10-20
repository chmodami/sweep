// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sweep",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Sweep", path: "Sources/Sweep")
    ]
)
