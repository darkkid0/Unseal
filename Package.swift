// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Unseal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Unseal",
            targets: ["AppModule"]
        )
    ],
    targets: [
        .target(
            name: "UnsealCore",
            path: "Sources/UnsealCore"
        ),
        .executableTarget(
            name: "AppModule",
            dependencies: [
                "UnsealCore"
            ],
            path: "Sources/AppModule",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "UnsealCoreTests",
            dependencies: [
                "UnsealCore"
            ],
            path: "Tests/UnsealCoreTests"
        )
    ]
)
