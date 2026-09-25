// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Graphite",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "GraphiteUI", targets: ["GraphiteUI"]),
        .library(name: "GraphiteCore", targets: ["GraphiteCore"]),
        .library(name: "GraphiteApple", targets: ["GraphiteApple"]),
        .executable(name: "GraphiteBenchmarks", targets: ["GraphiteBenchmarks"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        // Vendored Textual 0.5.0 with Graphite's patches, each listed in Vendor/textual/GRAPHITE-PATCHES.md.
        .package(path: "Vendor/textual"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")
    ],
    targets: [
        .target(name: "GraphiteCore", dependencies: [
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "Yams", package: "Yams")
        ]),
        .target(name: "GraphiteIndex", dependencies: ["GraphiteCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "GraphiteApple", dependencies: ["GraphiteCore"]),
        .target(name: "GraphiteUI", dependencies: ["GraphiteCore", "GraphiteIndex", "GraphiteApple", .product(name: "Textual", package: "textual")]),
        .executableTarget(name: "GraphiteBenchmarks", dependencies: ["GraphiteCore", "GraphiteIndex"]),
        .testTarget(name: "GraphiteCoreTests", dependencies: ["GraphiteCore"]),
        .testTarget(name: "GraphiteIndexTests", dependencies: ["GraphiteIndex", "GraphiteBenchmarks"]),
        .testTarget(name: "GraphiteAppleTests", dependencies: ["GraphiteApple"]),
        .testTarget(name: "GraphiteUITests", dependencies: ["GraphiteUI", .product(name: "Textual", package: "textual")])
    ]
)
