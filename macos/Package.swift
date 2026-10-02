// swift-tools-version: 5.9
import PackageDescription

// 应用名 2026-10-03 由 `deepGit` 改为 `deepDolphin`（与客户端仓同名）。
// 模块名跟着产品名走：target 名就是模块名，改一处即可，
// 但 `path` 那一行不会自动跟着改 —— 两者必须同时改，只改一个的症状是
// 「找不到 target Sources/deepGit」。
let package = Package(
    name: "deepDolphin",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "deepDolphin", targets: ["deepDolphin"])
    ],
    targets: [
        .executableTarget(
            name: "deepDolphin",
            path: "Sources/deepDolphin"
        )
    ]
)
