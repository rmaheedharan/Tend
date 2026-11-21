// swift-tools-version: 6.2
// TendIngestion: the platform-neutral M2 ingestion layer (brief Definitions, ADR-0006).
// Imports only Foundation and TendCore (AC-M2-09 Rule 1). Builds and tests on Linux.
import PackageDescription

let package = Package(
    name: "TendIngestion",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TendIngestion", targets: ["TendIngestion"]),
    ],
    dependencies: [
        .package(path: "../TendCore"),
        .package(path: "../TendSourceScan"),
    ],
    targets: [
        .target(
            name: "TendIngestion",
            dependencies: [
                .product(name: "TendCore", package: "TendCore"),
            ],
            path: "Sources/TendIngestion"
        ),
        .testTarget(
            name: "TendIngestionTests",
            dependencies: [
                "TendIngestion",
                .product(name: "TendSourceScan", package: "TendSourceScan"),
            ],
            path: "Tests/TendIngestionTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
