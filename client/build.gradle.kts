import java.io.File
import org.jetbrains.compose.desktop.application.tasks.AbstractJPackageTask

// Canopy — Cambium 引擎的跨平台桌面客户端（Compose Multiplatform / BUI 能力的承接者）。
//
// 能力基准：PLATFORM-CHARTER.md C1–C11；对位实现参考 archive/bui（Rust + blenderui）
// 与 macos/（SwiftUI 基准）。引擎访问唯一通路：`cambium <命令> --json` 子进程。

plugins {
    kotlin("multiplatform") version "2.0.21"
    id("org.jetbrains.compose") version "1.7.3"
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.0.21"
}

group = "com.canopy"
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
                // WebView（JCEF/CEF）：只用于代码图谱 / 架构图两页的引擎 HTML 产物。
                implementation("io.github.kevinnzou:compose-webview-multiplatform:1.9.40")
                // WebView 的离屏渲染靠 JOGL；KCEF 只带主 jar，**各平台本地库必须显式声明**。
                // 二次验证抓到：缺本地库时 WebView 一组合就抛 UnsatisfiedLinkError(gluegen_rt)——
                // 此前被 WebRuntime 状态永不就绪的 bug 挡着，页面只显示空白，错误从未露出。
                // 目前只声明并验证了 linux-amd64（本客户端的打包目标平台）；其它平台未验证、不声明。
                runtimeOnly("org.jogamp.gluegen:gluegen-rt:2.5.0:natives-linux-amd64")
                runtimeOnly("org.jogamp.jogl:jogl-all:2.5.0:natives-linux-amd64")
                // 原生包钉版（见 JcefBundle.kt）：KCEF 的下载地址解析器要直接实现，它的两个参数类型来自 Ktor。
                // 版本必须跟 KCEF 自带的保持一致（2024.04.20.3 → Ktor 3.0.0），否则同一类两个版本上类路径。
                implementation("io.ktor:ktor-http:3.0.0")
                implementation("io.ktor:ktor-client-core:3.0.0")
            }
        }
        @OptIn(org.jetbrains.compose.ExperimentalComposeLibrary::class)
        jvmTest.dependencies {
            implementation(kotlin("test"))
            // Compose 自带的界面测试构件（离屏渲染 + 语义树，插件标了实验性）：只给「逐皮肤对比度体检」
            // （SkinContrastAudit）用——不建窗口就能把每套皮肤画成位图、逐段文字量对比度。不进发行包。
            implementation(compose.uiTestJUnit4)
        }
    }
}

// 桌面应用入口：gradle run 直接启动真窗口；nativeDistributions（jpackage 打包）在分发批次补。
compose.desktop.application {
    mainClass = "canopy.MainKt"
    // KCEF/JCEF（C6 收尾批：Markdown WebView）在 JDK17+ 完成反射初始化需要这两个 add-opens。
    // application.jvmArgs 落进 jpackage 的 --java-options（deb 分发同样生效）+ run 任务。
    jvmArgs("--add-opens", "java.desktop/sun.awt=ALL-UNNAMED")
    jvmArgs("--add-opens", "java.desktop/java.awt.peer=ALL-UNNAMED")
    nativeDistributions {
        modules("java.instrument", "java.management")
        targetFormats(org.jetbrains.compose.desktop.application.dsl.TargetFormat.Deb, org.jetbrains.compose.desktop.application.dsl.TargetFormat.AppImage)
        packageName = "canopy"
        packageVersion = "0.1.0"
        vendor = "Canopy"
        description = "Cambium 引擎的跨平台桌面客户端（Compose Multiplatform）"
        linux {
            menuGroup = "Development"
            shortcut = true
            // ⚠ 这里不能写 startupWMClass：Compose Gradle 插件 1.7.3 的 Linux DSL 没有这个属性
            //   （写了脚本编译就失败）。窗口的 WM_CLASS 实测是 canopy-MainKt（AWT 按主类名生成），
            //   与 desktop 文件名不一致——任务栏归组靠窗口管理器的模糊匹配，未验证。
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
        val src = File(layout.buildDirectory.get().asFile, "libs/canopy-client-jvm-0.1.0.jar")
        val dst = File(outDir, "canopy-client-jvm-0.1.0.jar")
        src.copyTo(dst, overwrite = true)
    }
}
tasks.matching { it.name == "jvmJar" }.configureEach {
    doLast {
        val outDir = File(layout.buildDirectory.get().asFile, "compose/tmp/main-release/proguard")
        outDir.mkdirs()
        val src = File(layout.buildDirectory.get().asFile, "libs/canopy-client-jvm-0.1.0.jar")
        val dst = File(outDir, "canopy-client-jvm-0.1.0.jar")
        src.copyTo(dst, overwrite = true)
    }
}

// KCEF/JCEF 的 add-opens 兜底：确保本地 gradle run（JavaExec）也带上（jvmTest 是 Test 任务，
// 不属于 JavaExec，不受影响）。与上面 application.jvmArgs 双保险。
tasks.withType(org.gradle.api.tasks.JavaExec::class.java).configureEach {
    jvmArgs("--add-opens", "java.desktop/sun.awt=ALL-UNNAMED")
    jvmArgs("--add-opens", "java.desktop/java.awt.peer=ALL-UNNAMED")
}
