// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenCaddy",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ScreenCaddy",
            dependencies: [],
            path: "Sources/ScreenCaddy",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "SupportFiles/Info.plist",
                ]),
            ]
        ),
    ]
)
