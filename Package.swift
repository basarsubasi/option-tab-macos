// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OptionTab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OptionTab", targets: ["OptionTab"])
    ],
    targets: [
        .executableTarget(
            name: "OptionTab",
            dependencies: [],
            path: "Sources/OptionTab",
            resources: [],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "OptionTabTests",
            dependencies: ["OptionTab"],
            path: "Tests/OptionTabTests"
        )
    ]
)