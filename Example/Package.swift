// swift-tools-version: 6.3
import PackageDescription

// Bookshelf is Splint's example app. This Swift package exists so
// `swift test` exercises BookshelfTests from `script/test` and CI;
// the `.executableTarget` shape lets `@main BookshelfApp` compile.
// SPM cannot produce a runnable `.app` bundle (no Info.plist, no
// bundle identifier), so to *run* the app on Mac or iOS Simulator,
// open `Example/Bookshelf.xcodeproj`.
let package = Package(
  name: "Bookshelf",
  platforms: [
    .iOS("26.4"),
    .macOS("26.4"),
  ],
  products: [
    .executable(name: "Bookshelf", targets: ["Bookshelf"])
  ],
  dependencies: [
    .package(name: "Splint", path: "../")
  ],
  targets: [
    .executableTarget(
      name: "Bookshelf",
      dependencies: ["Splint"],
      path: "Bookshelf"
    ),
    .testTarget(
      name: "BookshelfTests",
      dependencies: ["Bookshelf"],
      path: "BookshelfTests"
    ),
  ]
)
