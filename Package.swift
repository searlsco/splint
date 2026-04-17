// swift-tools-version: 6.2
import Foundation
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

// Benchmark target + package-benchmark dependency are env-var-gated so
// consumers of Splint never resolve them. Swift 6.1 Package Traits were the
// first choice but `Target.PluginUsage` has no `condition:` parameter, so
// BenchmarkPlugin usage forces package resolution regardless of trait state.
// Env-var gating is the pattern used by swift-collections, swift-nio, etc.
// for dev-only deps. `script/benchmark` exports `SPLINT_BENCHMARK=1`.
if ProcessInfo.processInfo.environment["SPLINT_BENCHMARK"] != nil {
  package.dependencies.append(
    .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.4.0")
  )
  package.targets.append(
    .executableTarget(
      name: "LensBenchmarks",
      dependencies: [
        "Splint",
        .product(name: "Benchmark", package: "package-benchmark"),
      ],
      path: "Benchmarks/LensBenchmarks",
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
      ]
    )
  )
}
