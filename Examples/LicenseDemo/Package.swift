// swift-tools-version: 6.2
import PackageDescription

// A tiny Mac app to try DodoLicense. Run it with `swift run` from this folder, or open this
// Package.swift in Xcode.
let package = Package(
    name: "LicenseDemo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "LicenseDemo",
            dependencies: [.product(name: "DodoLicense", package: "dodo-license")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
