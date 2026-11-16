// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChamberKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ChamberKit", targets: ["ChamberKit"])
    ],
    targets: [
        .target(
            name: "ChamberKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
