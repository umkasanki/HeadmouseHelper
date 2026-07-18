// swift-tools-version: 5.9
import PackageDescription

// HeadmouseCore — the pure, platform-independent core of HeadmouseHelper.
//
// Contains only logic with no macOS dependency: the Settings model, its JSON
// persistence, the device model, the seize *port* protocol, and the
// TrackingController state machine. It builds and tests on any platform.
//
// The macOS app (App/HeadmouseHelper) provides the concrete IOKit adapter and
// AppKit/SwiftUI UI, and consumes this package's compiled objects.

let package = Package(
    name: "HeadmouseCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HeadmouseCore", targets: ["HeadmouseCore"]),
    ],
    targets: [
        .target(
            name: "HeadmouseCore",
            path: "Sources/HeadmouseCore"
        ),
        .testTarget(
            name: "HeadmouseCoreTests",
            dependencies: ["HeadmouseCore"],
            path: "Tests/HeadmouseCoreTests"
        ),
    ]
)
