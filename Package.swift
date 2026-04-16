// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Splint",
  platforms: [
    .iOS("26.2"),
    .macOS("26.2"),
    .tvOS("26.2"),
    .watchOS("26.2"),
    .visionOS("26.2"),
  ],
  products: [
    .library(name: "Splint", targets: ["Splint"])
  ],
  targets: [
    .target(name: "Splint"),
    .testTarget(name: "SplintTests", dependencies: ["Splint"]),
  ]
)
