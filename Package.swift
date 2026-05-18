// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IssuetrackerSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "IssuetrackerSDK", targets: ["IssuetrackerSDK"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "IssuetrackerSDK",
            resources: [
                // Asset catalog hosting the onboarding illustrations.
                // Empty until the SVGs are dropped in; declaring the
                // resource here is what emits a Bundle.module, so the
                // asset lookup in OnboardingView resolves at runtime
                // (and falls back to SF Symbols when the catalog
                // doesn't yet contain the named image).
                .process("Resources/Onboarding.xcassets")
            ]
        ),
        .testTarget(
            name: "IssuetrackerSDKTests",
            dependencies: ["IssuetrackerSDK"],
            resources: [.copy("Resources/test-vectors.json")]
        ),
    ]
)
