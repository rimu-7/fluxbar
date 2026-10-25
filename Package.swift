// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ClipCore", targets: ["ClipCore"]),
        .library(name: "NetCore", targets: ["NetCore"]),
        .library(name: "PowerCore", targets: ["PowerCore"]),
        .executable(name: "NotchKit", targets: ["NotchKit"]),
        .executable(name: "nkit", targets: ["nkit"]),
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
        .target(
            name: "NetCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/NetCore"
        ),
        .target(
            name: "PowerCore",
            dependencies: [],
            path: "Sources/PowerCore"
        ),
        .executableTarget(
            name: "NotchKit",
            dependencies: [
                "ClipCore",
                "NetCore",
                "PowerCore"
            ],
            path: "Sources/NotchKit"
        ),
        .executableTarget(
            name: "nkit",
            dependencies: [
                "ClipCore",
                "PowerCore",
                "NetCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/nkit"
        ),
        .executableTarget(
            name: "com.notchkit.powerd",
            dependencies: [
                "PowerCore"
            ],
            path: "Sources/PowerDaemon",
            resources: [
                .copy("com.notchkit.powerd.plist")
            ]
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
        ),
        .testTarget(
            name: "NetCoreTests",
            dependencies: [
                "NetCore"
            ],
            path: "Tests/NetCoreTests"
        ),
        .testTarget(
            name: "PowerCoreTests",
            dependencies: [
                "PowerCore"
            ],
            path: "Tests/PowerCoreTests"
        )
    ]
)
