// swift-tools-version: 6.2
import PackageDescription

// The same settings as Dodo's own Swift SDK (DodoCheckout): Swift 6 language mode and
// approachable concurrency, without making the whole library main-actor by default.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "DodoLicense",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DodoLicense", targets: ["DodoLicense"])
    ],
    targets: [
        .target(
            name: "DodoLicense",
            path: "Sources/DodoLicense",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "DodoLicenseTests",
            dependencies: ["DodoLicense"],
            path: "Tests/DodoLicenseTests",
            swiftSettings: swiftSettings
        ),
    ]
)
