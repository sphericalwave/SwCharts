// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwCharts",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwCharts", targets: ["SwCharts"]),
    ],
    targets: [
        .target(name: "SwCharts"),
        .testTarget(name: "SwChartsTests", dependencies: ["SwCharts"]),
    ]
)
