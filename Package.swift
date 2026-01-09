// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "timed",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "timed", targets: ["timed"])
    ],
    targets: [
        .executableTarget(
            name: "timed"
        )
    ]
)
