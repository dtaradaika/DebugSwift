// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DebugSwift",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "DebugSwift",
            targets: ["DebugSwift"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", from: "4.11.0")
    ],
    targets: [
        .target(
            name: "DebugSwift",
            dependencies: [
                .product(name: "SQLCipher", package: "SQLCipher.swift")
            ],
            path: "DebugSwift",
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .define("SQLITE_HAS_CODEC", to: "1")
            ],
            swiftSettings: [
                .define("SQLITE_HAS_CODEC")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
