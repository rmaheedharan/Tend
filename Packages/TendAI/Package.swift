// swift-tools-version: 6.2
// TendAI: the Apple-framework adapters (FoundationModels, Speech) and the BYOK cloud adapters behind the TendIngestion
// protocols (ADR-0006; M2 plan "Module and file layout"). Apple-only: it is never built on Linux.
// Scaffold from WI-M2-M1; the adapters arrive in WI-M2-M2…M6. AC-M2-09 Rules 2, 3 and 5 scan `Sources/TendAI`.
// `HostedTests/` holds the tests that need an iOS host app; `project.yml` builds them as `TendAIHostedTests`.
import PackageDescription

let package = Package(
    name: "TendAI",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TendAI", targets: ["TendAI"]),
    ],
    dependencies: [
        .package(path: "../TendCore"),
        .package(path: "../TendIngestion"),
    ],
    targets: [
        .target(
            name: "TendAI",
            dependencies: [
                .product(name: "TendCore", package: "TendCore"),
                .product(name: "TendIngestion", package: "TendIngestion"),
            ],
            path: "Sources/TendAI"
        ),
        .testTarget(
            name: "TendAITests",
            dependencies: ["TendAI"],
            path: "Tests/TendAITests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
