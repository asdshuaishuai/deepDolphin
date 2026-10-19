// ArchReceipt.h — 引擎回执文本的提取（纯函数层，零 QWidget 头）。
//
// 【为什么单独抽】
// 架构图的「生成 / 导出」是**回执型命令**：引擎 stdout 是人话（多行），
// 不是 JSON。客户端要从中取两样东西：
//   · 回执末行 —— 给用户看的一句话结果（mac ArchPageVM.receipt 同款口径）；
//   · 导出路径 —— `render arch` 的落盘 HTML 绝对路径（mac extractHTMLPath 同款）。
// 这两件事看着像字符串处理，实则**很容易悄悄错**：末行判定漏了空行会拿到
// 空串，路径判定把相对路径当绝对路径会让「打开导出文件」按钮永远打不开。
// 抽成纯函数后可在无图形环境里逐条判。
#pragma once
#include <QString>

namespace ArchReceipt {

/// 回执末行：去掉尾部空行后的**最后一个非空行**。全空 → 返回空串。
QString receipt(const QString &text);

/// 从回执里抽出落盘文件的**绝对路径**（以 `suffix` 结尾且以 / 开头）。
/// 抽不到 → 返回空串（**不猜**：相对路径不认，宁可没有「打开」入口）。
///
/// suffix 形如 ".html" / ".md"。抽路径的规则只有一份（词边界 + 绝对路径），
/// 各命令（render arch 出 .html、report 出 .md）只是传不同的后缀。
QString filePath(const QString &text, const QString &suffix);

/// 从回执里抽出落盘的 HTML 绝对路径（`filePath(text, ".html")` 的特例）。
QString htmlPath(const QString &text);

/// 去掉 ANSI 转义序列（引擎回执的颜色码）。
///
/// ⚠ 引擎的 `report` 成功行带颜色（`\x1b[32m✓\x1b[0m`），而引擎**不认**
///   `NO_COLOR`（实测 2026-10-19：设了照样带码）。这串转义直接塞进 QLabel，
///   用户看到的是「[32m✓[0m 报告已生成：…」—— 回执里的关键信息被乱码埋了。
///   剥色只动显示层，不动回执原文（引擎说什么就是什么）。
QString plain(const QString &text);

} // namespace ArchReceipt
