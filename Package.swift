// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VantaSpeech",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VantaSpeechCore",
            targets: ["VantaSpeechCore"]
        ),
    ],
    dependencies: [
        // FFmpegKit for audio conversion to OGG/Opus
        // Full version includes all codecs including libopus
        .package(
            url: "https://github.com/arthenica/ffmpeg-kit-spm.git",
            from: "6.0.0"
        ),
    ],
    targets: [
        .target(
            name: "VantaSpeechCore",
            dependencies: [
                .product(name: "ffmpeg-kit-ios-full", package: "ffmpeg-kit-spm")
            ],
            path: "VantaSpeech/Core"
        ),
        .testTarget(
            name: "VantaSpeechCoreTests",
            dependencies: ["VantaSpeechCore"],
            path: "Tests"
        ),
    ]
)
