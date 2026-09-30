// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "deepGit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "deepGit", targets: ["deepGit"])
    ],
    targets: [
        .executableTarget(
            name: "deepGit",
            path: "Sources/deepGit"
        )
    ]
)
