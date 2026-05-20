// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "hyperliquid-swift-sdk",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15),
    ],
    products: [
        .library(
            name: "HyperliquidSwift",
            targets: ["HyperliquidSwift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", exact: "0.16.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "HyperliquidSwift",
            dependencies: [
                .product(name: "secp256k1", package: "secp256k1.swift"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ],
            path: "Sources/HyperliquidSwift"
        ),
    ]
)
