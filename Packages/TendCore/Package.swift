// swift-tools-version: 6.2
// TendCore: the pure-Swift household engine (CLAUDE.md §3, ADR-0001).
// Foundation only, no UI, no Apple-only frameworks, buildable and testable on Linux.
import PackageDescription

let package = Package(
    name: "TendCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TendCore", targets: ["TendCore"]),
    ],
    targets: [
        .target(
            name: "TendCore",
            path: "Sources/TendCore"
        ),
        .testTarget(
            name: "TendCoreTests",
            dependencies: ["TendCore"],
            path: "Tests/TendCoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
