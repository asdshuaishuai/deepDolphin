// JcefBundle.kt —— 图谱页 WebView 的原生包（JCEF/CEF）从哪来、钉在哪个版本。
//
// 【为什么必须钉死】KCEF 的默认下载是 `github()`：拉 JetBrainsRuntime 的**最新** release。
// 而 Java 绑定（dev.datlag:jcef）是 Maven 上的定版——原生与绑定必须同源，否则：
//   实测 2026-11-23 下到的是 Chromium 150 的 JBR 25，原生按名字找
//   org.cef.browser.CefRequestContextSettings（新 JBR 才有的类），旧绑定里没有——
//   加载真实 URL 必经此处，ClassNotFoundException 之后进程直接 SIGSEGV。
// 这不是偶发：绑定停在 2024-10-15，「最新」却天天在走，装得越晚越对不上。
//
// 【钉的是哪个构建】jbr_jcef-21.0.4-linux-x64-b631.2（2024-10-14，与绑定编译日期同期）。
// 同源依据：该包 jcef 模块与绑定 jar 的 222 个公共 org.cef 类逐类比过成员签名，只有 5 个类
// 在纯 Java 辅助方法上有出入，native 方法签名全部一致——JNI 契约就是同一份。
//
// 【为什么走 JetBrains CDN】GitHub 上旧 release 的二进制已被清掉（下载链接 404），
// cache-redirector 上的历史构建长期保留（IntelliJ 自己下 JBR 也走这里）。

package canopy.ui

import dev.datlag.kcef.KCEFBuilder
import io.ktor.client.HttpClient
import io.ktor.client.statement.HttpResponse
import io.ktor.http.Url

internal object JcefBundle {

    /** 与 Java 绑定同源的 JBR 构建标识——同时是安装目录的子目录名：换构建即换目录，绝不复用别的原生包。 */
    const val ID = "jbr-21.0.4+8-631.2"

    private const val CDN = "https://cache-redirector.jetbrains.com/intellij-jbr"

    /** 已验证平台 → 包直链。目前只有 linux-x64（本客户端的打包目标；JOGL 本地库也只声明了它）。 */
    private val PACKAGES = mapOf(
        "linux-x64" to "$CDN/jbr_jcef-21.0.4-linux-x64-b631.2.tar.gz",
    )

    /** 当前平台的钉死包地址；null = 未验证平台（调用方退回 KCEF 默认下载）。 */
    fun urlFor(osName: String = System.getProperty("os.name"), osArch: String = System.getProperty("os.arch")): String? {
        val os = when {
            osName.startsWith("Linux", ignoreCase = true) -> "linux"
            else -> return null
        }
        val arch = when (osArch) {
            "amd64", "x86_64" -> "x64"
            else -> return null
        }
        return PACKAGES["$os-$arch"]
    }

    /**
     * KCEF 的下载分两步：先 GET download.url，再问地址解析器要真正的包地址。
     * 所以首个请求落到体积很小的 .checksum 上（二百多 MB 的包只下一次），包地址直接给钉死的直链。
     */
    fun resolver(bundleUrl: String): KCEFBuilder.Download.Transform = object : KCEFBuilder.Download.Transform {
        override suspend fun transform(client: HttpClient, response: HttpResponse): Url = Url(bundleUrl)
    }
}
