// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pelmet",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Pure geometry/classification — no window-server or UI calls,
        // so the notch-overflow logic stays unit-testable.
        .target(
            name: "PelmetCore",
            path: "Sources/PelmetCore"
        ),
        .executableTarget(
            name: "Pelmet",
            dependencies: ["PelmetCore"],
            path: "Sources/Pelmet"
        ),
        .testTarget(
            name: "PelmetCoreTests",
            dependencies: ["PelmetCore"],
            path: "Tests/PelmetCoreTests"
        ),
    ],
    // Tools 6.0 is needed for Swift Testing; the app itself stays in the
    // Swift 5 language mode (no strict-concurrency migration yet).
    swiftLanguageModes: [.v5]
)
