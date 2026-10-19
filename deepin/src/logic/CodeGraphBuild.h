// CodeGraphBuild.h — 三份引擎输出 → 一棵代码图谱（纯函数层，零 QWidget 头）。
//
// 【为什么单独抽】
// 合成规则里藏着三处**最容易悄悄错**的地方：
//   ① 符号 id：`graph tree` 的 symbols **不带 id**，客户端要按
//      `f:<路径>:<行号>:<名字>` 构造 —— 而 `graph functions` 的 functions
//      **带** id，两边要能对上，靠的就是这个构造式与引擎一致。
//   ② 疑点归属：函数级疑点（functions 侧）已按符号体归属好；置信度侧
//      （confidence）那份是**全仓疑点**，要按「文件+行号+kind」去掉已归属的，
//      剩下的才是「孤儿」挂到文件上。不去重 → 同一个疑点被数两遍。
//   ③ 汇总卷积：rollN（子树疑点数）与 rollW（子树最高权重）自底向上算，
//      算错会让树上的徽标与详情页对不上。
// 这三处都不该等到看图才发现 —— 故抽成纯函数直接判。
#pragma once
#include <QJsonObject>
#include <QString>
#include <QVector>
#include "../models/CodeGraph.h"

namespace CodeGraphBuild {

/// 三份引擎输出。
struct Source {
    QJsonObject tree;       ///< graph tree <项目> --json
    QJsonObject confidence; ///< graph confidence <项目> --json
    QJsonObject functions;  ///< graph functions <项目> --json
};

/// 合成结果。
struct Result {
    bool ok = false;
    QString error; ///< 失败时说清是**哪一种**（缺 tree / 缺 confidence / 缺 functions）

    CodeGraph graph;

    int score = 0;             ///< 置信度总分
    QString astNote;           ///< 语法树不可用时的降级说明（引擎原话）
    bool astUsed = false;
    QVector<GraphFinding> findings;      ///< 全仓疑点（confidence 侧）
    QHash<QString, QString> snippets;    ///< 符号 id → 源码片段
    QVector<GraphSymEdge> symEdges;     ///< 符号级调用边
    QVector<GraphFileEdge> fileEdges;   ///< 文件级引用边

    // 截断披露（**缺键不得当作「没有」**：引擎发 0 也发，但客户端仍要能说清
    // 「有多少被跳过」—— 0 与「没发」在值上不可区分，故各自留 present 标志）。
    bool truncated = false;
    bool truncatedPresent = false;
    int skipped = 0;
    bool skippedPresent = false;
    int oversizeSkipped = 0;
    bool oversizeSkippedPresent = false;
    int depth = 0;
    bool depthOmitted = false;
    QStringList unreadableDirs;
    bool unreadableDirsTruncated = false;
};

/// 合成。
/// @param projectName 锁定的项目名（root 节点名取它的末段）。
Result build(const Source &src, const QString &projectName);

/// 符号 id 的**唯一构造式**（引擎 `graph functions` 的 id 与之同形）。
/// 单独给出是因为「构造式」是 id 能对上的关键，出处必须唯一。
QString symbolId(const QString &path, int line, const QString &name);

/// 行扁平化（按展开态与搜索词算出可见行）。
/// @param expanded 展开的节点 id 集合
/// @param query 搜索词（空 = 不过滤）
QVector<GraphTreeRow> visibleRows(const CodeGraph &g, const QStringList &expanded,
    const QString &query);

/// 疑点归属键（文件+行号+kind）—— 归属与去重共用同一把钥匙。
QString findingKey(const QString &file, int line, const QString &kind);

} // namespace CodeGraphBuild
