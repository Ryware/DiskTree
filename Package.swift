// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskTree",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiskTree", targets: ["DiskTree"])
    ],
    targets: [
        .executableTarget(
            name: "DiskTree",
            path: "Sources/DiskTree",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
