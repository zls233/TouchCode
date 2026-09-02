// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TouchCodeMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TouchCodeMac", targets: ["TouchCodeMac"])
    ],
    targets: [
        .target(
            name: "TouchCodeIdentity",
            path: "Sources/TouchCodeIdentity"
        ),
        .executableTarget(
            name: "TouchCodeMac",
            dependencies: ["TouchCodeIdentity"],
            path: "Sources/TouchCodeMac"
        ),
        .testTarget(
            name: "TouchCodeIdentityTests",
            dependencies: ["TouchCodeIdentity"],
            path: "Tests/TouchCodeIdentityTests"
        )
    ]
)
