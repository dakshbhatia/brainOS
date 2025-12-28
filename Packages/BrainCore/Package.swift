// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrainCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BrainCore", targets: ["BrainCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.88.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/orlandos-nl/IkigaJSON", from: "2.3.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.29.1"),
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            revision: "74f85d9505032ec3403c94ba159472244fe78767"
        ),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.2"),
        .package(url: "https://github.com/mediar-ai/MacosUseSDK.git", branch: "main"),
        .package(path: "../BrainRepository"),
    ],
    targets: [
        .target(
            name: "BrainCore",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "IkigaJSON", package: "IkigaJSON"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "MacosUseSDK", package: "MacosUseSDK"),
                .product(name: "BrainRepository", package: "BrainRepository"),
            ],
            path: ".",
            exclude: ["Tests"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "BrainCoreTests",
            dependencies: [
                "BrainCore",
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ],
            path: "Tests"
        ),
    ]
)
