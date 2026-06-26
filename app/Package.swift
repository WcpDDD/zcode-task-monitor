// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZCodeTaskMonitor",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ZCodeTaskMonitor",
            path: "Sources/ZCodeTaskMonitor",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
