// CodeGraph.h — 代码图谱页的数据模型（mac CodeGraphPage.swift 的 GNode/GFinding 对位）。
//
// 【为什么用「扁平 arena + 索引」而不是嵌套树】
// 树上要做两件事：① 按祖先链展开（选中一个符号时把路径上的目录都打开）；
// ② 按 id 查节点（关系页签的调用方/被调方）。嵌套 `QVector<GraphNode> kids`
// 里的裸指针在扩容时会失效 —— 所以这里把节点摊平成一个 arena，
// 父子关系用**索引**表达（索引在 arena 里是稳定的）。
//
// 【数据来自三个引擎命令，形状各不相同】
//   · `graph tree <项目> --json`      → 文件骨架 + 符号清单 + 引用边
//   · `graph confidence <项目> --json` → 总分、维度、疑点清单
//   · `graph functions <项目> --json` → 函数级归属 + 源码片段 + 符号级调用边
// 三份合成一棵树的规则在 `logic/CodeGraphBuild`（纯函数，可无头判）。
#pragma once
#include <QHash>
#include <QString>
#include <QStringList>
#include <QVector>

/// 节点种类：根 → 目录 → 文件 → 符号。
enum class GraphNodeKind {
    root,
    dir,
    file,
    sym,
};

/// 一条疑点（置信度侧的结构性疑点：孤儿/占位/吞错/魔法数/重复体…）。
struct GraphFinding {
    QString kind;   ///< 原始 id，如 high-complexity
    QString label;  ///< 人类可读，如 圈复杂度过高（可能缺失）
    QString dim;    ///< 分组维度 variable/function/…（可能缺失）
    QString file;
    int line = 0;
    int weight = 0;
    QString evidence;
};

/// 符号级调用边（来自 `graph functions` 的 functionEdges）。
struct GraphSymEdge {
    QString from, to;
    int weight = 1;
    QString tier = QStringLiteral("resolved"); ///< resolved / guessed（guessed 画虚线）
};

/// 文件级引用边（来自 `graph tree` 的 referenceEdges，元素是 [from,to,w]）。
struct GraphFileEdge {
    QString from, to;
    int weight = 1;
};

/// 树节点（arena 里的一个）。
struct GraphNode {
    GraphNodeKind kind = GraphNodeKind::root;
    QString id;
    QString name;
    QString path;    ///< dir/file：相对路径；sym：所在文件路径
    QString lang;
    QString symKind; ///< 符号种类（func/class/…）
    int lines = 0;
    int declLine = 0;
    int parent = -1;    ///< 父节点在 arena 里的索引（-1 = 无）
    QVector<int> kids;  ///< 子节点索引

    QVector<GraphFinding> ownFindings; ///< 本节点直接挂着的疑点

    // 汇总（自底向上卷积得出）。
    int rollN = 0;   ///< 子树疑点总数
    int rollW = 0;   ///< 子树最高权重（徽标档位色）
    int rollWeightSum = 0; ///< 子树疑点**权重和**（热色的输入：置信度分数按罚分算）
    int fileCount = 0; ///< 子树文件数
};

/// 一行树（深度用于缩进）。
struct GraphTreeRow {
    int node = -1; ///< arena 索引
    int depth = 0;
};

/// 整棵代码图谱。
struct CodeGraph {
    QVector<GraphNode> nodes;
    int root = -1;
    QHash<QString, int> indexById;
    QVector<GraphTreeRow> rows;   ///< 展平后的可见行（随展开态/搜索重建）
    QStringList expanded;         ///< 展开的节点 id
    QString rootName;

    bool isEmpty() const { return root < 0; }
    const GraphNode *node(int idx) const
    {
        return idx >= 0 && idx < nodes.size() ? &nodes.at(idx) : nullptr;
    }
    int indexOf(const QString &id) const { return indexById.value(id, -1); }
};
