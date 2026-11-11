// swift-tools-version: 6.2
import PackageDescription

/// The same upcoming language features as the pingfront SDK (pingfront-ios).
let upcoming: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),  // SE-0461
    .enableUpcomingFeature("InferIsolatedConformances"),  // SE-0470
    .enableUpcomingFeature("ExistentialAny"),  // SE-0335
    .enableUpcomingFeature("MemberImportVisibility"),  // SE-0444
    .enableUpcomingFeature("InternalImportsByDefault"),  // SE-0409
]

/// The pingfront adapter for Superwall.
///
/// Placements become offer slots, offer cards register the placement.
/// It is its own package, so an app that adds it fetches Superwall and nothing from the other vendors.
let package = Package(
    name: "PingFrontSuperwall",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PingFrontSuperwall", targets: ["PingFrontSuperwall"])
    ],
    dependencies: [
        .package(url: "https://github.com/pingfront/pingfront-ios", from: "1.0.0"),
        .package(url: "https://github.com/pingfront/pingfront-ios-adapter-kit", from: "1.0.0"),
        // Current stable major, as built and tested here: SuperwallKit 4.
        .package(url: "https://github.com/superwall/Superwall-iOS.git", from: "4.18.3"),
    ],
    targets: [
        .target(
            name: "PingFrontSuperwall",
            dependencies: [
                .product(name: "PingFrontAdapterKit", package: "pingfront-ios-adapter-kit"),
                .product(name: "PingFrontCore", package: "pingfront-ios"),
                // SuperwallKit builds for iOS only (it imports UIKit); on macOS the adapter's logic still builds and tests.
                .product(name: "SuperwallKit", package: "Superwall-iOS", condition: .when(platforms: [.iOS])),
            ],
            swiftSettings: upcoming
        ),
        .testTarget(
            name: "PingFrontSuperwallTests",
            dependencies: [
                "PingFrontSuperwall",
                .product(name: "PingFrontAdapterKit", package: "pingfront-ios-adapter-kit"),
                .product(name: "PingFrontAdapterTestSupport", package: "pingfront-ios-adapter-kit"),
                .product(name: "PingFrontCore", package: "pingfront-ios"),
            ],
            swiftSettings: upcoming
        ),
    ],
    swiftLanguageModes: [.v6]
)
