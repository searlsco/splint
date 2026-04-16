// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "Splint",
  platforms: [
    .iOS("26.4"),
    .macOS("26.4"),
    .tvOS("26.4"),
    .watchOS("26.4"),
    .visionOS("26.4"),
  ],
  products: [
    .library(name: "Splint", targets: ["Splint"])
  ],
  targets: [
    .target(name: "Splint"),
    .testTarget(name: "SplintTests", dependencies: ["Splint"]),
  ]
)
