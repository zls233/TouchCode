// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TouchCodeMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TouchCodeMac", targets: ["TouchCodeMac"])
    ],
    targets: [
        .executableTarget(
            name: "TouchCodeMac",
            path: "Sources/TouchCodeMac"
        )
    ]
)

