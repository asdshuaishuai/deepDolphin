// GraphInsight.h — 图谱三件套（`graph overview` / `graph symbol` / `graph impact`）
// 的判定层（纯函数，零 QWidget 头）。
//
// 【为什么要单独一层】这三件套有三处容易「错得毫无声响」：
//   ① **引擎只认符号名**：`graph symbol` / `graph impact` 传符号 id
//      （`f:路径:行号:名字`）进去，引擎返回 `{}` —— 看着像「这个符号没有影响面」，
//      实际是有影响面的（客户端明明持有 id，却传错了形态）。
//      判定层把「id → 名字」这一层固化，界面只管传名字。
//   ② **符号不存在不是错误**：引擎对查不到的符号返回
//      `{"name": "...", "defs": []}` 且退出码 0 —— 界面必须显示
//      「没找到这个符号」，而不是一片空白（更不能当成契约坏了）。
//   ③ **影响面是词法近似**：引擎自己标了 `granularity: lexical-file-level`，
//      截断时还有 `refFilesCapped` / `impactedCapped` —— 不披露就成了
//      「完整的影响面」，那是假的。
#pragma once
#include <QJsonObject>
#include <QMap>
#include <QString>
#include <QStringList>
#include <QVector>

namespace GraphInsight {

/// 符号 id（`f:<路径>:<行号>:<名字>`）→ **符号名**。
///
/// ⚠ 引擎的 `graph symbol` / `graph impact` 只认名字。传 id 会返回空结果，
///   而空结果看着像「没有影响面」。故客户端一律先取名字再问引擎。
///   id 形状认不出时返回空串（调用方据此说明「传不了」，不猜名字）。
QString symbolNameFromId(const QString &id);

/// 一个定义点。
struct Def {
    QString file;
    int line = 0;
    QString kind;
};

/// 一个引用来源（`graph symbol` 的 referencedBy：文件 + 权重）。
struct Ref {
    QString file;
    int weight = 0;
};

/// 一个受影响的符号（`graph impact` 的 impactedSymbols）。
struct Impacted {
    QString file;
    QString symbol;
    QString kind;
};

/// `graph overview` 的结果（项目级概览）。
struct Overview {
    bool ok = false;
    QString error;
    QString root;
    int files = 0;
    int symbols = 0;
    int imports = 0;
    int referenceEdges = 0;
    /// 符号最多的文件（引擎给的 topFiles）。
    QVector<Def> topFiles; ///< Def 只用 file；symbols/lines 另存
    QVector<int> topFileSymbols;
    QVector<int> topFileLines;
    QMap<QString, int> byLang;
    QMap<QString, int> byKind;
    bool truncated = false;
    int skipped = 0;
    int oversizeSkipped = 0;
    QStringList unreadableDirs;
    bool unreadableDirsTruncated = false;
};

/// `graph symbol` 的结果。
struct SymbolDetail {
    bool ok = false;
    QString error;
    QString name;
    QVector<Def> defs;
    QVector<Ref> referencedBy;

    /// 符号**找到了没有**（引擎对不存在的符号返回空 defs 且退出码 0）。
    bool found() const { return !defs.isEmpty(); }
};

/// `graph impact` 的结果。
struct Impact {
    bool ok = false;
    QString error;
    QString name;
    QVector<Def> defs;
    QStringList refFiles;
    QVector<Impacted> impactedSymbols;
    QString granularity;
    bool refFilesCapped = false;
    bool impactedCapped = false;

    /// 有没有被截断（披露用）。
    bool capped() const { return refFilesCapped || impactedCapped; }
};

/// 解析 `graph overview` 的载荷。
Overview parseOverview(const QJsonObject &o);

/// 解析 `graph symbol` 的载荷。
SymbolDetail parseSymbol(const QJsonObject &o);

/// 解析 `graph impact` 的载荷。
Impact parseImpact(const QJsonObject &o);

} // namespace GraphInsight
