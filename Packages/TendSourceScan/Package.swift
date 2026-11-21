// swift-tools-version: 6.2
// TendSourceScan: the Swift source lexer and the AC-M2-09 rule engine (ADR-0006, M2 plan WI-M2-01).
// Test-only library: Foundation only, linked only into test targets, never into an app or extension target.
import PackageDescription

let package = Package(
    name: "TendSourceScan",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TendSourceScan", targets: ["TendSourceScan"]),
    ],
    targets: [
        .target(
            name: "TendSourceScan",
            path: "Sources/TendSourceScan"
        ),
        .testTarget(
            name: "TendSourceScanTests",
            dependencies: ["TendSourceScan"],
            path: "Tests/TendSourceScanTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
