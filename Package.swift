// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iMD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "iMD",
            targets: ["iMD"]
        )
    ],
    targets: [
        .executableTarget(
            name: "iMD",
            path: "Sources"
        )
    ]
)
