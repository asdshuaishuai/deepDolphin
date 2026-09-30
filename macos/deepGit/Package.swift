// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "deepGit",
    platforms: [.macOS(.v14)],
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
