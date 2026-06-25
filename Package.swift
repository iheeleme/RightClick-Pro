// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RightTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RightToolCore", targets: ["RightToolCore"]),
        .executable(name: "righttool-action-runner", targets: ["RightToolActionRunnerService"]),
        .executable(name: "righttool-app-preview", targets: ["RightToolAppPreview"])
    ],
    dependencies: [],
    targets: [
        .target(name: "RightToolCore"),
        .executableTarget(
            name: "RightToolActionRunnerService",
            dependencies: ["RightToolCore"]
        ),
        .executableTarget(
            name: "RightToolAppPreview",
            dependencies: ["RightToolCore"]
        ),
        .target(
            name: "RightToolFinderExtension",
            dependencies: ["RightToolCore"]
        ),
        .testTarget(
            name: "RightToolCoreTests",
            dependencies: ["RightToolCore"]
        )
    ]
)
