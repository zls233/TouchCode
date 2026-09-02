// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TouchCodeMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TouchCodeMac", targets: ["TouchCodeMac"]),
        .executable(name: "TouchCodeIdentityHelper", targets: ["TouchCodeIdentityHelper"])
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
        .executableTarget(
            name: "TouchCodeIdentityHelper",
            dependencies: ["TouchCodeIdentity"],
            path: "Sources/TouchCodeIdentityHelper"
        ),
        .testTarget(
            name: "TouchCodeIdentityTests",
            dependencies: ["TouchCodeIdentity"],
            path: "Tests/TouchCodeIdentityTests"
        ),
        .testTarget(
            name: "TouchCodeMacTests",
            dependencies: ["TouchCodeMac"],
            path: "Tests/TouchCodeMacTests"
        )
    ]
)
