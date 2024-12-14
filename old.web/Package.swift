// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ScreenExtender",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .executable(
            name: "MacScreenExtender",
            targets: ["MacScreenExtender"]
        ),
        .executable(
            name: "iOSScreenExtender",
            targets: ["iOSScreenExtender"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacScreenExtender",
            dependencies: [],
            path: "MacScreenExtender/Sources",
            exclude: ["iOSScreenExtender"]
        ),
        ),
        .executableTarget(
            name: "iOSScreenExtender",
            path: "iOSScreenExtender/Sources",
            resources: [
                .process("Shaders.metal")
            ]
        )
    ]
) 