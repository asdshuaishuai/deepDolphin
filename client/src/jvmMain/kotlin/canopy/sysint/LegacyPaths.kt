// LegacyPaths.kt —— 品牌升级（deepDolphin → Canopy，2026-11-26）后的本机迁移。
//
// 【为什么要有这个】应用改名会连带改掉落在用户家目录里的路径：配置目录、缓存目录、自启条目的文件名。
// 直接换名字的话，用户的皮肤 / 语言 / 定时档 / API key 会在升级后「凭空消失」，400MB 的 WebView 原生包
// 要重新下载，旧的自启条目还会在开机时去拉已经卸掉的旧程序。所以改名的那一侧要负责把旧位置的东西接过来。
//
// 【纪律】只搬不改内容、搬不动就继续用旧的：
//   · 整目录改名（同分区、原子），内容一个字节不动；
//   · 新旧都在 → 用新的，旧的原样留着不动（不删用户的东西）；
//   · 改名失败（跨分区、权限）→ 继续用旧目录，设置不丢。
// 引擎那边正相反——它的数据目录与托管标记属于「既有数据与外部契约」，按引擎仓库的硬边界**不改名**
// （见 Cambium 的 README「改名字，不改身份」）。两边不是同一种东西：这里是应用自己的私有目录。
package canopy.sysint

import java.io.File

/** 旧品牌的目录名（迁移的来源）。 */
const val LEGACY_APP_DIR = "deepDolphin"

/** 旧品牌的自启条目文件名。 */
const val LEGACY_AUTOSTART_FILE = "deepdolphin.desktop"

/**
 * 品牌升级后的目录：`parent/name`。新目录不存在而旧目录在 → 整目录改名搬过去；
 * 搬不动就返回旧目录（调用方照常读写，设置不丢）；两边都在或都不在 → 新目录。
 */
fun migratedDir(parent: File, name: String, legacyName: String = LEGACY_APP_DIR): File {
    val current = File(parent, name)
    val legacy = File(parent, legacyName)
    if (!current.exists() && legacy.exists()) {
        if (legacy.renameTo(current)) return current
        return legacy
    }
    return current
}

/**
 * 品牌升级后的自启条目：旧条目（[LEGACY_AUTOSTART_FILE]）还在、新条目没有 → 用当前客户端入口重写一份
 * 新的并删掉旧的（旧条目的 Exec 指向旧安装路径，升级后那个程序已经不在了；留着还会与新的重复自启）。
 * [clientEntry] 为 null（开发态：入口不是打包后的 launcher）→ 不动，如实返回「没迁」。
 *
 * 返回三态：Migrated（已迁）/ NotNeeded（没有旧条目）/ Skipped（有旧条目但这次没法迁）。
 */
fun migrateLegacyAutostart(dir: File, clientEntry: String?): AutostartMigration {
    val legacy = File(dir, LEGACY_AUTOSTART_FILE)
    if (!legacy.isFile) return AutostartMigration.NotNeeded
    if (clientEntry == null) return AutostartMigration.Skipped
    val err = SysInt.setAutostart(dir, clientEntry, true)
    return if (err == null) AutostartMigration.Migrated else AutostartMigration.Skipped
}

enum class AutostartMigration { Migrated, NotNeeded, Skipped }
