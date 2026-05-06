// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RadioPlayer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RadioPlayer",
            path: "Sources/RadioPlayer",
            linkerSettings: [
                .linkedFramework("MediaPlayer"),
                .linkedFramework("AVFoundation"),
            ]
        )
    ]
)
