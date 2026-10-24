// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipSuite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ClipCore", targets: ["ClipCore"]),
        .executable(name: "ClipBar", targets: ["ClipBar"]),
        .executable(name: "clip", targets: ["clip"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0")
    ],
    targets: [
        .target(
            name: "ClipCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/ClipCore"
        ),
        .executableTarget(
            name: "ClipBar",
            dependencies: [
                "ClipCore"
            ],
            path: "Sources/ClipBar"
        ),
        .executableTarget(
            name: "clip",
            dependencies: [
                "ClipCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/clip"
        ),
        .testTarget(
            name: "ClipCoreTests",
            dependencies: [
                "ClipCore"
            ],
            path: "Tests/ClipCoreTests"
        )
    ]
)
