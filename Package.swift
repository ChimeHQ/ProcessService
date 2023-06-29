// swift-tools-version:5.5

import PackageDescription

let settings: [SwiftSetting] = [
//	.unsafeFlags(["-Xfrontend", "-strict-concurrency=complete"])
]

let package = Package(
    name: "ProcessService",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "ProcessServiceServer", targets: ["ProcessServiceServer"]),
        .library(name: "ProcessServiceClient", targets: ["ProcessServiceClient"]),
		.library(name: "ProcessServiceContainer", targets: ["ProcessServiceContainer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/ProcessEnv", from: "0.3.1"),
		.package(url: "https://github.com/mattmassicotte/Queue", from: "0.1.3"),
		.package(url: "https://github.com/ChimeHQ/AsyncXPCConnection", branch: "main"),
    ],
    targets: [
        .target(name: "ProcessServiceShared"),
        .target(
			name: "ProcessServiceServer",
			dependencies: ["ProcessServiceShared", "ProcessEnv"],
			swiftSettings: settings
		),
        .target(
			name: "ProcessServiceClient",
			dependencies: ["AsyncXPCConnection", "ProcessServiceShared", "ProcessEnv", "Queue"],
			swiftSettings: settings
		),
		.binaryTarget(
			name: "ProcessServiceContainer",
			path: "ProcessServiceContainer.xcframework"
		),

		.testTarget(
			name: "ProcessServiceClientTests",
			dependencies: ["ProcessServiceClient", "ProcessServiceContainer"],
			swiftSettings: settings
		),
		.testTarget(
			name: "ProcessServiceServerTests",
			dependencies: ["ProcessServiceServer"],
			swiftSettings: settings),
    ]
)
