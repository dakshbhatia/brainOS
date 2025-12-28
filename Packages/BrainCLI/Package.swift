// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrainCLI",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "brain-cli", targets: ["BrainCLI"]),
        .library(name: "BrainCLICore", targets: ["BrainCLICore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(path: "../BrainRepository"),
    ],
    targets: [
        .executableTarget(
            name: "BrainCLI",
            dependencies: [
                "BrainCLICore"
            ]
        ),
        .target(
            name: "BrainCLICore",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "BrainRepository", package: "BrainRepository"),
            ]
        ),
        .testTarget(
            name: "BrainCLITests",
            dependencies: ["BrainCLICore"]
        ),
    ]
)
