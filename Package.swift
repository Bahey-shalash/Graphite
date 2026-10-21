// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Graphite",
    platforms: [.iOS("27.0"), .macOS("27.0")],
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
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        // A trimmed copy of mlx-audio-swift (MIT) that runs the downloadable Read Aloud voices;
        // its changes from upstream are listed in Vendor/mlx-audio-swift/GRAPHITE-PATCHES.md.
        .package(path: "Vendor/mlx-audio-swift"),
        // Standalone packages (Docs/solid/rewrite-foundations.md section 3.5): they know nothing of Graphite.
        .package(path: "Packages/NotebookImport")
    ],
    targets: [
        .target(name: "GraphiteCore", dependencies: [
            .product(name: "Markdown", package: "swift-markdown"),
            .product(name: "Yams", package: "Yams")
        ]),
        .target(name: "GraphiteIndex", dependencies: ["GraphiteCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "GraphiteApple", dependencies: ["GraphiteCore", .product(name: "NotebookImport", package: "NotebookImport")], resources: [.copy("Resources/MathSpeech")]),
        // The on-device neural voices: model loading and rendering with MLX.
        .target(name: "GraphiteVoices", dependencies: ["GraphiteCore", "GraphiteApple", .product(name: "MLXAudioTTS", package: "mlx-audio-swift")],
                resources: [.copy("Resources/NeuralVoices.json"), .copy("Resources/DiaVoicePrompt.json")]),
        .target(name: "GraphiteUI", dependencies: ["GraphiteCore", "GraphiteIndex", "GraphiteApple", "GraphiteVoices", .product(name: "Textual", package: "textual")],
                // The Obsidian plugin runtime's page, scripts and vendored libraries, copied as
                // one folder so the page's relative script paths keep working.
                // The theme resolver's default variables and probe script (`ThemeTokenResolver`).
                resources: [.copy("Resources/CommunityPluginRuntime"), .copy("Resources/ThemeResolver")]),
        .executableTarget(name: "GraphiteBenchmarks", dependencies: ["GraphiteCore", "GraphiteIndex"]),
        // Fakes and helpers the test targets share (temporary vaults, isolated preferences, the one polling
        // wait, the conflict-version fake). It imports XCTest, so only test targets depend on it.
        .target(name: "GraphiteTestSupport", dependencies: ["GraphiteCore", "GraphiteApple"], path: "Tests/GraphiteTestSupport"),
        // Where the checked-in fixture vaults under `Tests/` are found, for every test target that reads one.
        .target(name: "GraphiteFixtures", path: "Tests/GraphiteFixtures"),
        // The babbling clip is a real Qwen3-TTS rendering, to test the checks on real audio.
        .testTarget(name: "GraphiteCoreTests", dependencies: ["GraphiteCore", "GraphiteTestSupport", "GraphiteFixtures"], resources: [.copy("Resources/QwenBabbling.m4a")]),
        .testTarget(name: "GraphiteIndexTests", dependencies: ["GraphiteIndex", "GraphiteBenchmarks", "GraphiteTestSupport", "GraphiteFixtures"]),
        .testTarget(name: "GraphiteAppleTests", dependencies: ["GraphiteApple", "GraphiteTestSupport", .product(name: "NotebookImport", package: "NotebookImport")]),
        .testTarget(name: "GraphiteUITests", dependencies: ["GraphiteUI", "GraphiteTestSupport", .product(name: "Textual", package: "textual")])
    ]
)
