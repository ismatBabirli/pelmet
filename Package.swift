// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pelmet",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Pelmet",
            path: "Sources/Pelmet"
        )
    ]
)
