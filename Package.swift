// swift-tools-version: 5.10
// Test-only package: compiles the app's UI-free sources so `swift test` can run in CI.
// The app itself is built from DesknetApp.xcodeproj.
import PackageDescription

let package = Package(
    name: "DesknetCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "DesknetCore",
            path: "DesknetApp",
            exclude: [
                "Views", "Window", "Assets.xcassets", "desknet_hook.py",
                "App/DesknetApp.swift", "App/MainMenu.swift",
            ],
            sources: ["Models", "Services", "ViewModels", "App/HookPrompt.swift"]
        ),
        .testTarget(
            name: "DesknetCoreTests",
            dependencies: ["DesknetCore"],
            path: "Tests/DesknetCoreTests"
        ),
    ]
)
