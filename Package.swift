// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RightClickPro",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RightClickProCore", targets: ["RightClickProCore"]),
        .executable(name: "rightclickpro-action-runner", targets: ["RightClickProActionRunnerService"]),
        .executable(name: "rightclickpro-app-preview", targets: ["RightClickProAppPreview"])
    ],
    dependencies: [],
    targets: [
        .target(name: "RightClickProCore"),
        .executableTarget(
            name: "RightClickProActionRunnerService",
            dependencies: ["RightClickProCore"]
        ),
        .executableTarget(
            name: "RightClickProAppPreview",
            dependencies: ["RightClickProCore"]
        ),
        .target(
            name: "RightClickProFinderExtension",
            dependencies: ["RightClickProCore"]
        ),
        .testTarget(
            name: "RightClickProCoreTests",
            dependencies: ["RightClickProCore"]
        )
    ]
)
