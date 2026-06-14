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
            exclude: ["Resources/Info.plist"],
            resources: [],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/OptionTab/Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "OptionTabTests",
            dependencies: ["OptionTab"],
            path: "Tests/OptionTabTests"
        )
    ]
)