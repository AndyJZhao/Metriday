// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Metriday",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Metriday", targets: ["MetridayApp"])
    ],
    targets: [
        .executableTarget(
            name: "MetridayApp",
            path: "Sources/MetridayApp"
        )
    ]
)
