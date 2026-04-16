// swift-tools-version: 6.3
import PackageDescription

// Bookshelf is Splint's example app. It is wired up as a Swift package
// for `swift build` reachability in CI and local tooling. To run the
// app, open this directory in Xcode 26.4+ and use the `BookshelfApp`
// scheme (Xcode will generate an iOS app target automatically from the
// Swift package product when the `App` scene is present).
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
