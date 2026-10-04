// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iText",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "iText",
            targets: ["iText"]
        )
    ],
    targets: [
        .executableTarget(
            name: "iText",
            path: "Sources"
        )
    ]
)
