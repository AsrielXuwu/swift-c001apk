// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoolapkKit",
    platforms: [
        .iOS("27.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "CoolapkKit", targets: ["CoolapkKit"])
    ],
    targets: [
        .target(
            name: "CoolapkKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CoolapkKitTests",
            dependencies: ["CoolapkKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
