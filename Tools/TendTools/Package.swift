// swift-tools-version: 6.2
// TendTools: command-line tools for the M2 eval and the cloud payload (plan "Module and file layout", "Scoring tool and
// command"; ADR-0006). It sits outside `TendIngestion/Sources`, so it may read files and print (AC-M2-09 Rule 1, T-26).
// It is never linked into an app target. No third-party dependency: arguments are parsed by hand.
import PackageDescription

let package = Package(
    name: "TendTools",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "tend-eval-score", targets: ["tend-eval-score"]),
        .executable(name: "tend-payload-dump", targets: ["tend-payload-dump"]),
    ],
    dependencies: [
        .package(path: "../../Packages/TendIngestion"),
    ],
    targets: [
        .target(
            name: "TendToolsSupport",
            dependencies: [.product(name: "TendIngestion", package: "TendIngestion")],
            path: "Sources/TendToolsSupport"
        ),
        .executableTarget(name: "tend-eval-score", dependencies: ["TendToolsSupport"], path: "Sources/tend-eval-score"),
        .executableTarget(name: "tend-payload-dump", dependencies: ["TendToolsSupport"], path: "Sources/tend-payload-dump"),
        .testTarget(name: "TendToolsTests", dependencies: ["TendToolsSupport"], path: "Tests/TendToolsTests"),
    ],
    swiftLanguageModes: [.v6]
)
