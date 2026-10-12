// swift-tools-version:6.2
import PackageDescription

// A trimmed copy of mlx-audio-swift (MIT, https://github.com/Blaizzy/mlx-audio-swift at 244458d)
// holding only what Graphite's Read Aloud voices need. Every change from upstream is listed in
// GRAPHITE-PATCHES.md.
let package = Package(
    name: "MLXAudio",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MLXAudioCore", targets: ["MLXAudioCore"]),
        .library(name: "MLXAudioTTS", targets: ["MLXAudioTTS"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.32.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.3.4"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "0.12.0")
    ],
    targets: [
        .target(
            name: "MLXAudioCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface")
            ],
            path: "Sources/MLXAudioCore"
        ),
        .target(
            name: "MLXAudioCodecs",
            dependencies: [
                "MLXAudioCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "Sources/MLXAudioCodecs"
        ),
        .target(
            name: "MLXAudioG2P",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift")
            ],
            path: "Sources/MLXAudioG2P"
        ),
        .target(
            name: "MLXAudioTTS",
            dependencies: [
                "MLXAudioCore",
                "MLXAudioCodecs",
                "MLXAudioG2P",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "Sources/MLXAudioTTS"
        )
    ]
)
