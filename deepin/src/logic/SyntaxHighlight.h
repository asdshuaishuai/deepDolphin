// SyntaxHighlight.h — 源码高亮的**判定层**（纯函数，零 QWidget 头）。
//
// 【为什么单独一层】高亮的判定是「这一段是关键字还是字符串还是注释」——
// 纯字符串问题，与控件无关。抽出来可无头判：分类错了（把关键字染成字符串、
// 把字符串里的 # 当注释）在界面上只是「颜色怪了点」，不测就永远发现不了。
//
// 【九种语言与引擎对齐】引擎的 `graph/extract.cj:detectLang` 恰好产出九种语言：
// swift / cangjie / ts / python / go / rust / java / kotlin / c（其余返回 ""）。
// 本层的语言集合与之**一一对应** —— 引擎报什么语言，这里就得能高亮什么语言；
// 对不上时那些文件的源码会是一片纯色（看不出是代码还是文本）。
// 契约门（第 16 组）用真引擎跑九种扩展名，断言两边集合相等。
//
// 【四类 token】与 mac 的 `SyntaxHighlight.highlight` 同款语义：
// 关键字 / 字符串 / 注释 / 数字。颜色由 UI 层从 DS 令牌取（判定层不碰颜色 ——
// 颜色是主题的事，不是判定的事）。
#pragma once
#include <QSet>
#include <QString>
#include <QVector>

namespace SyntaxHighlight {

/// token 类别（plain = 未分类，判定层不产出 —— 界面默认色即可）。
enum class Kind { plain, keyword, string, comment, number };

/// 一段已分类的 token。
struct Span {
    int start = 0; ///< 在行内的起始字符下标（UTF-16 码元，与 QString 下标一致）
    int len = 0;
    Kind kind = Kind::plain;
};

/// 客户端支持的语言集合（与引擎 `detectLang` 的九种一一对应；单一真相源）。
QVector<QString> languages();

/// 是否是该语言（引擎报的 lang 原样传进来即可）。
bool supportsLanguage(const QString &lang);

/// 某语言的关键词集；不认识的语言回落到 cangjie（与 mac 同款：仓颉是本项目的主语言）。
QSet<QString> keywords(const QString &lang);

/// 行注释前缀（python 用 `#`，其余用 `//`；与 mac 同款）。
QString lineCommentPrefix(const QString &lang);

/// 高亮一行 → 已分类的段。
///
/// · 单遍扫描 O(n)；段按 `start` 升序、**互不重叠**；
/// · 整行是注释（trim 后以注释前缀开头）→ 返回一整段 comment；
/// · 字符串/注释的着色**吃到引号/行尾**（含闭合引号）—— 半截着色的字符串最难看；
/// · 未分类的部分不产出段（界面用默认色）。
QVector<Span> highlight(const QString &line, const QString &lang);

} // namespace SyntaxHighlight
