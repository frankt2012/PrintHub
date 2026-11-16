// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChamberSpike",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CrealityKit", targets: ["CrealityKit"]),
        .library(name: "CameraKit", targets: ["CameraKit"]),
        .executable(name: "chamber-spike", targets: ["ChamberSpikeCLI"])
    ],
    targets: [
        // Download script: Tools/fetch-webrtc.sh (Vendor/ is git-ignored).
        .binaryTarget(
            name: "WebRTC",
            path: "Vendor/WebRTC.xcframework"
        ),
        .target(
            name: "CrealityKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "CameraKit",
            dependencies: ["WebRTC"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ChamberSpikeCLI",
            dependencies: ["CrealityKit", "CameraKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CrealityKitTests",
            dependencies: ["CrealityKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CameraKitTests",
            dependencies: ["CameraKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
