// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OldPhoneDeck",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DeckAgents",
            path: "Sources/DeckAgents",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "oldphonedeck",
            dependencies: ["DeckAgents"],
            path: "Sources/oldphonedeck",
            resources: [.copy("web")],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(
            name: "DeckAgentsTests",
            dependencies: ["DeckAgents"],
            path: "Tests/DeckAgentsTests",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
