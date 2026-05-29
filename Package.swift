// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastEditorApp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FastEditorApp",
            path: "Sources/FastEditorApp"
        )
    ]
)
