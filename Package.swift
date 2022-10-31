// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ProcessService",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "ProcessServiceServer", targets: ["ProcessServiceServer"]),
        .library(name: "ProcessServiceClient", targets: ["ProcessServiceClient"]),
		.library(name: "ProcessServiceContainer", targets: ["ProcessServiceContainer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/ConcurrencyPlus", from: "0.4.0"),
        .package(url: "https://github.com/ChimeHQ/ProcessEnv", from: "0.3.1"),
    ],
    targets: [
        .target(name: "ProcessServiceShared"),
        .target(name: "ProcessServiceServer", dependencies: ["ProcessServiceShared", "ConcurrencyPlus", "ProcessEnv"]),
        .target(name: "ProcessServiceClient", dependencies: ["ProcessServiceShared", "ConcurrencyPlus", "ProcessEnv"]),
		.binaryTarget(name: "ProcessServiceContainer", path: "ProcessServiceContainer.xcframework"),

		.testTarget(name: "ProcessServiceClientTests", dependencies: ["ProcessServiceClient", "ConcurrencyPlus", "ProcessServiceContainer"]),
		.testTarget(name: "ProcessServiceServerTests", dependencies: ["ProcessServiceServer", "ConcurrencyPlus"]),
    ]
)
