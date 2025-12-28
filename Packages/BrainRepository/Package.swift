// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrainRepository",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BrainRepository", targets: ["BrainRepository"])
    ],
    targets: [
        .target(
            name: "BrainRepository",
            path: "."
        )
    ]
)
