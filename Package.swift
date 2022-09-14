// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ProcessService",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "ProcessServiceServer", targets: ["ProcessServiceServer"]),
        .library(name: "ProcessServiceClient", targets: ["ProcessServiceClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/ConcurrencyPlus", from: "0.3.1"),
        .package(url: "https://github.com/ChimeHQ/ProcessEnv", from: "0.3.0"),
    ],
    targets: [
        .target(name: "ProcessServiceShared"),
        .target(name: "ProcessServiceServer", dependencies: ["ProcessServiceShared", "ConcurrencyPlus", "ProcessEnv"]),
        .target(name: "ProcessServiceClient", dependencies: ["ProcessServiceShared", "ConcurrencyPlus", "ProcessEnv"]),

		.testTarget(name: "ProcessServiceServerTests", dependencies: ["ProcessServiceServer", "ConcurrencyPlus"]),
    ]
)
