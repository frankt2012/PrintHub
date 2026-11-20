// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrintHubKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PrintHubKit", targets: ["PrintHubKit"])
    ],
    targets: [
        .target(
            name: "PrintHubKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
