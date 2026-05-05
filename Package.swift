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
        .target(name: "IssuetrackerSDK"),
    ]
)
