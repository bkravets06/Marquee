// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarqueeKit",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [
        .library(name: "MarqueeKit", targets: ["MarqueeKit"])
    ],
    targets: [
        .target(name: "MarqueeKit"),
        .testTarget(
            name: "MarqueeKitTests",
            dependencies: ["MarqueeKit"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
