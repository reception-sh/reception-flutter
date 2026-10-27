// swift-tools-version: 6.0
import PackageDescription

// The Reception iOS SDK sources are compiled into this target (Sources/reception_flutter/Vendor/Reception),
// so the plugin needs no CocoaPods Trunk or remote package. tool/sync_ios_sdk.dart keeps them pinned.
let package = Package(
    name: "reception_flutter",
    defaultLocalization: "en",
    platforms: [.iOS("17.0")],
    products: [.library(name: "reception-flutter", targets: ["reception_flutter"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "reception_flutter",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
            exclude: ["Vendor/Reception/LICENSE"],
            resources: [.process("Vendor/Reception/Sources/Reception/Resources")],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ],
    swiftLanguageModes: [.v5]
)
