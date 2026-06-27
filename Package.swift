// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScoreDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScoreDock", targets: ["ScoreDock"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ScoreDock",
            dependencies: [],
            path: "Sources/ScoreDock"
        )
    ]
)
