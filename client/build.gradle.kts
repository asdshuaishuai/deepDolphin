import java.io.File
import org.jetbrains.compose.desktop.application.tasks.AbstractJPackageTask

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
    nativeDistributions {
        modules("java.instrument", "java.management")
        targetFormats(org.jetbrains.compose.desktop.application.dsl.TargetFormat.Deb, org.jetbrains.compose.desktop.application.dsl.TargetFormat.AppImage)
        packageName = "deepdolphin"
        packageVersion = "0.1.0"
        vendor = "deepDolphin"
        description = "moonGit 引擎的跨平台桌面客户端（Compose Multiplatform）"
        linux {
            menuGroup = "Development"
            shortcut = true
        }
    }
}


// ProGuard 7.2.2（CMP 1.7.3 默认）吃不了 JDK21 class（65.0）且插件 classpath 项目级
// 无法升级——禁用 proguard 任务，launcher 主 jar 显式指回未混淆产物（jpackage 合法输入）。

// 禁 proguard：输入断链修补——packageRelease* 的 launcherMainJar 由 proguard 输出改为
// build/libs 的原 jar（tasks.withType 在配置期改 @InputFile 路径）。
// proguard 禁用 + 输出占位：proguard 任务 disabled 后 package 任务仍校验其输出路径存在——
// 用 finalizer 化的拷贝把原 jar 放到 proguard 的期望输出位置（对抗插件 DSL 的最小侵入法）。
tasks.matching { it.name.startsWith("proguard") }.configureEach {
    enabled = false
    doLast {
        val outDir = File(layout.buildDirectory.get().asFile, "compose/tmp/main-release/proguard")
        outDir.mkdirs()
        val src = File(layout.buildDirectory.get().asFile, "libs/deepdolphin-client-jvm-0.1.0.jar")
        val dst = File(outDir, "deepdolphin-client-jvm-0.1.0.jar")
        src.copyTo(dst, overwrite = true)
    }
}
tasks.matching { it.name == "jvmJar" }.configureEach {
    doLast {
        val outDir = File(layout.buildDirectory.get().asFile, "compose/tmp/main-release/proguard")
        outDir.mkdirs()
        val src = File(layout.buildDirectory.get().asFile, "libs/deepdolphin-client-jvm-0.1.0.jar")
        val dst = File(outDir, "deepdolphin-client-jvm-0.1.0.jar")
        src.copyTo(dst, overwrite = true)
    }
}
