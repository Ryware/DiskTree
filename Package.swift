// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Headroom", targets: ["Headroom"])
    ],
    targets: [
        .executableTarget(
            name: "Headroom",
            path: "Sources/Headroom",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "HeadroomTests",
            dependencies: ["Headroom"],
            path: "Tests/HeadroomTests"
        ),
    ]
)
