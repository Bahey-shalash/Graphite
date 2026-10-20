// swift-tools-version: 6.0
// Vendored copy of SwiftUIMath 0.1.0 (https://github.com/gonzalezreal/swiftui-math, MIT).
// See GRAPHITE-PATCHES.md for the changes Graphite carries.

import PackageDescription

let package = Package(
  name: "swiftui-math",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "SwiftUIMath", targets: ["SwiftUIMath"])
  ],
  targets: [
    .target(
      name: "SwiftUIMath",
      dependencies: [],
      resources: [.copy("mathFonts.bundle")]
    )
  ]
)
