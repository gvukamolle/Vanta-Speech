// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VantaSpeech",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "VantaSpeech",
            targets: ["VantaSpeech"]
        ),
    ],
    dependencies: [
        // FFmpegKit for audio conversion to OGG/Opus
        .package(
            url: "https://github.com/arthenica/ffmpeg-kit-spm.git",
            from: "6.0.0"
        ),
    ],
    targets: [
        .target(
            name: "VantaSpeech",
            dependencies: [
                .product(name: "ffmpeg-kit-ios-full", package: "ffmpeg-kit-spm")
            ],
            path: "VantaSpeech",
            exclude: [
                "Resources/Info.plist",
                "Resources/VantaSpeech.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "VantaSpeechTests",
            dependencies: ["VantaSpeech"],
            path: "Tests"
        ),
    ]
)
