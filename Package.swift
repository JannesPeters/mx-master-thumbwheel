// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ThumbwheelRemapper",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "ThumbwheelRemapperCore",
            targets: ["ThumbwheelRemapperCore"]
        ),
        .executable(
            name: "ThumbwheelRemapper",
            targets: ["ThumbwheelRemapper"]
        ),
    ],
    targets: [
        .target(
            name: "ThumbwheelRemapperCore",
            path: "Sources/ThumbwheelRemapperCore"
        ),
        .executableTarget(
            name: "ThumbwheelRemapper",
            dependencies: ["ThumbwheelRemapperCore"],
            path: "Sources/ThumbwheelRemapper"
        ),
        .testTarget(
            name: "ThumbwheelRemapperCoreTests",
            dependencies: ["ThumbwheelRemapperCore"],
            path: "Tests/ThumbwheelRemapperCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
