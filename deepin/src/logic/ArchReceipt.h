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

/// 从回执里抽出落盘的 HTML 绝对路径（以 .html 结尾且以 / 开头）。
/// 抽不到 → 返回空串（**不猜**：相对路径不认，宁可没有「打开」入口）。
QString htmlPath(const QString &text);

} // namespace ArchReceipt
