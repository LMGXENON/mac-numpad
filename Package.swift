// swift-tools-version: 6.0
import PackageDescription

// Built with ./build.sh (swiftc directly, Swift 5 language mode), because this
// CLT's manifest library exposes no language-mode settings. Package.swift is
// kept for editor tooling only.
let package = Package(
    name: "TouchPadKeypad",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(name: "TouchPadKeypad")
    ]
)
