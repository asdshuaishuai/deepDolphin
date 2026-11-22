// deepDolphin — moonGit 引擎的跨平台桌面客户端（Compose Multiplatform / BUI 能力的承接者）。
//
// 能力基准：PLATFORM-CHARTER.md C1–C11；对位实现参考 archive/bui（Rust + blenderui）
// 与 macos/（SwiftUI 基准）。引擎访问唯一通路：`moongit <命令> --json` 子进程。

plugins {
    kotlin("multiplatform") version "2.0.21"
    id("org.jetbrains.compose") version "1.7.3"
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.0.21"
}

group = "com.deepdolphin"
version = "0.1.0"

kotlin {
    jvmToolchain(21)
    jvm()

    sourceSets {
        val jvmMain by getting {
            dependencies {
                implementation(compose.desktop.currentOs)
                implementation(compose.foundation)
                implementation(compose.material3)
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.9.0")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
                // WebView（Linux/macOS/Windows 走 JCEF/CEF；用于 Markdown / AI 对话渲染）
                implementation("io.github.kevinnzou:compose-webview-multiplatform:1.9.40")
            }
        }
        jvmTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

// 桌面应用入口：gradle run 直接启动真窗口；nativeDistributions（jpackage 打包）在分发批次补。
compose.desktop.application {
    mainClass = "deepdolphin.MainKt"
}
