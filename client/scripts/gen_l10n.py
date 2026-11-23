#!/usr/bin/env python3
# gen_l10n.py —— 从 mac 基准（macos/Sources/deepDolphin/L10n.swift + DocsPages.swift）
# 提取四语言（zh-CN / en / zh-TW / ja）键值表与 16 份固定文档，生成 Kotlin 资源
# L10nTables.kt。【纪律】文案照搬不改写；键集以 mac 为准全量搬运（504 键 × 4 语言）。
#
# 用法（仓库根执行）：
#   python3 client/scripts/gen_l10n.py            # 生成并打印差异摘要
#   python3 client/scripts/gen_l10n.py --check    # 只校验已生成文件是否与基准一致（CI 守门）
#
# 输出：client/src/jvmMain/kotlin/deepdolphin/ui/L10nTables.kt（勿手改；CMP 特有键
# 追加在 L10nCmpKeys.kt，与生成文件分开——重跑本脚本不覆盖手写键）。

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
L10N_SWIFT = ROOT / "macos/Sources/deepDolphin/L10n.swift"
DOCS_SWIFT = ROOT / "macos/Sources/deepDolphin/DocsPages.swift"
OUT = ROOT / "client/src/jvmMain/kotlin/deepdolphin/ui/L10nTables.kt"

TABLES = [
    ("L10n_zhCN", "L10N_ZH_CN", "简体中文"),
    ("L10n_en", "L10N_EN", "English"),
    ("L10n_zhTW", "L10N_ZH_TW", "繁體中文"),
    ("L10n_ja", "L10N_JA", "日本語"),
]

DOCS = [
    # (Swift 常量名, Kotlin 常量名, DocKind, 语言)
    ("aboutZhCN", "ABOUT_ZH_CN", "ABOUT", "ZH_CN"),
    ("aboutEn", "ABOUT_EN", "ABOUT", "EN"),
    ("aboutZhTW", "ABOUT_ZH_TW", "ABOUT", "ZH_TW"),
    ("aboutJa", "ABOUT_JA", "ABOUT", "JA"),
    ("helpZhCN", "HELP_ZH_CN", "HELP", "ZH_CN"),
    ("helpEn", "HELP_EN", "HELP", "EN"),
    ("helpZhTW", "HELP_ZH_TW", "HELP", "ZH_TW"),
    ("helpJa", "HELP_JA", "HELP", "JA"),
    ("openSourceZhCN", "OPEN_SOURCE_ZH_CN", "OPEN_SOURCE", "ZH_CN"),
    ("openSourceEn", "OPEN_SOURCE_EN", "OPEN_SOURCE", "EN"),
    ("openSourceZhTW", "OPEN_SOURCE_ZH_TW", "OPEN_SOURCE", "ZH_TW"),
    ("openSourceJa", "OPEN_SOURCE_JA", "OPEN_SOURCE", "JA"),
    ("changelogZhCN", "CHANGELOG_ZH_CN", "CHANGELOG", "ZH_CN"),
    ("changelogEn", "CHANGELOG_EN", "CHANGELOG", "EN"),
    ("changelogZhTW", "CHANGELOG_ZH_TW", "CHANGELOG", "ZH_TW"),
    ("changelogJa", "CHANGELOG_JA", "CHANGELOG", "JA"),
]


def kt_escape(s: str) -> str:
    """Swift 字面量（已解码为原始字符串）→ Kotlin 转义。"""
    return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("$", "\\$")


def parse_tables(swift: str):
    """解析四个 `let L10n_xx: L10nTable = [...]` 字典字面量 → {name: [(key, value)]}。"""
    out = {}
    for swift_name, _, _ in TABLES:
        m = re.search(
            r"let " + swift_name + r": L10nTable = \[(.*?)\n\]", swift, re.S
        )
        if not m:
            sys.exit(f"L10n.swift 里找不到 {swift_name} 字典")
        body = re.sub(r"//[^\n]*", "", m.group(1))  # 去行注释（值里没有 //，真机核对过）
        pairs = re.findall(r'"((?:[^"\\]|\\.)+)"\s*:\s*"((?:[^"\\]|\\.)*)"', body)
        keys = [k for k, _ in pairs]
        if len(keys) != len(set(keys)):
            dup = sorted({k for k in keys if keys.count(k) > 1})
            sys.exit(f"{swift_name} 有重复键：{dup}")
        out[swift_name] = pairs
    return out


def parse_docs(swift: str):
    """解析 DocsPages.swift 的 16 个多行字符串（三引号）。"""
    out = {}
    for swift_name, _, _, _ in DOCS:
        m = re.search(
            r"static let " + swift_name + r' = """\n(.*?)\n    """', swift, re.S
        )
        if not m:
            sys.exit(f"DocsPages.swift 里找不到 {swift_name}")
        out[swift_name] = m.group(1)
    return out


def main():
    tables = parse_tables(L10N_SWIFT.read_text())
    docs = parse_docs(DOCS_SWIFT.read_text())

    base = [k for k, _ in tables["L10n_zhCN"]]
    for swift_name, _, label in TABLES:
        keys = [k for k, _ in tables[swift_name]]
        if set(keys) != set(base):
            missing = set(base) - set(keys)
            extra = set(keys) - set(base)
            sys.exit(f"{label} 键集与 zh-CN 不齐：缺 {sorted(missing)} 多 {sorted(extra)}")

    lines = [
        "// L10nTables.kt —— 四语言字符串表 + 四文档（GENERATED，勿手改）。",
        "// 由 client/scripts/gen_l10n.py 从 mac 基准生成：",
        "//   macos/Sources/deepDolphin/L10n.swift（504 键 × zh-CN/en/zh-TW/ja）",
        "//   macos/Sources/deepDolphin/DocsPages.swift（关于/帮助/开源感谢/更新日志 × 四语言）",
        "// 【纪律】文案照搬不改写；改文案请改 mac 基准后重跑脚本。",
        "// CMP 特有键（mac 没有的）追加在 L10nCmpKeys.kt，不在本文件。",
        "@file:Suppress(\"unused\")",
        "",
        "package deepdolphin.ui",
        "",
    ]
    for (swift_name, kt_name, label), _ in zip(TABLES, TABLES):
        lines.append(f"/** {label}（对位 mac {swift_name}，顺序同源）。 */")
        lines.append(f"internal val {kt_name}: Map<String, String> = mapOf(")
        for k, v in tables[swift_name]:
            lines.append(f'    "{kt_escape(k)}" to "{kt_escape(v)}",')
        lines.append(")")
        lines.append("")

    lines.append("/** 固定长文（对位 mac DocPages；content(kind, language) 分发）。 */")
    lines.append("internal object DocPagesText {")
    for swift_name, kt_name, kind, lang in DOCS:
        text = docs[swift_name]
        # Kotlin 原始字符串（"""）；内容里没有三引号与 $（脚本对基准校验过），
        # 但仍防御性断言，防未来基准变更带入模板注入。
        assert '"""' not in text and "$" not in text, f"{swift_name} 含 \"\"\" 或 $"
        # Swift 多行字符串按关闭引号缩进 dedent：mac 源里统一 4 空格，生成侧不再保留
        body = "\n".join(ln[4:] if ln.startswith("    ") else ln for ln in text.split("\n"))
        lines.append(f"    internal val {kt_name}: String = \"\"\"")
        lines.append(body)
        lines.append('    """')
        lines.append("")
    lines.append("    /** (kind, language) → 文档原文；对位 mac DocPages.content。 */")
    lines.append("    fun content(kind: DocKind, language: AppLanguage): String = when (kind) {")
    kinds = []
    for _, _, kind, _ in DOCS:
        if kind not in kinds:
            kinds.append(kind)
    for kind in kinds:
        lines.append(f"        DocKind.{kind} -> when (language) {{")
        for _, kt_name, k2, lang in DOCS:
            if k2 == kind:
                lines.append(f"            AppLanguage.{lang} -> {kt_name}")
        lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")

    generated = "\n".join(lines)
    if "--check" in sys.argv:
        current = OUT.read_text() if OUT.exists() else ""
        if current != generated:
            sys.exit("L10nTables.kt 与 mac 基准不一致——重跑 gen_l10n.py 再提交")
        print(f"OK: L10nTables.kt 与基准一致（{len(base)} 键 × 4 语言 + 16 文档）")
        return
    OUT.write_text(generated)
    print(f"生成 {OUT}（{len(base)} 键 × 4 语言，{len(DOCS)} 文档）")


if __name__ == "__main__":
    main()
