// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-cat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ClaudeCatCore", targets: ["ClaudeCatCore"]),
        .executable(name: "claude-cat", targets: ["ClaudeCatCLI"]),
        .executable(name: "claude-cat-app", targets: ["ClaudeCatApp"])
    ],
    targets: [
        .target(name: "ClaudeCatCore"),
        .target(name: "ClaudeCatPet", dependencies: ["ClaudeCatCore"]),
        .executableTarget(
            name: "ClaudeCatCLI",
            dependencies: ["ClaudeCatCore"]
        ),
        .executableTarget(
            name: "ClaudeCatApp",
            dependencies: ["ClaudeCatCore", "ClaudeCatPet"]
        ),
        .testTarget(
            name: "ClaudeCatCoreTests",
            dependencies: ["ClaudeCatCore"]
        ),
        .testTarget(
            name: "ClaudeCatPetTests",
            dependencies: ["ClaudeCatPet"]
        ),
        .testTarget(
            name: "ClaudeCatAppTests",
            dependencies: ["ClaudeCatApp", "ClaudeCatPet"]
        )
    ]
)
