// HeatLayout.h — 代码图谱「符号索引热力图」的布局与走线（纯函数层，零 QWidget 头）。
//
// 【这是什么】
// mac 的 `CodeGraphHeatmap.swift`（693 行）里，**核心算法约 380 行**（卡片铺排 +
// 重心扫描 + 通道车道走线），其余是 SwiftUI 外壳。本文件移植的是那 380 行 —���
// 铺排与走线都是纯计算，与图形栈无关，故放判定层。
//
// 【口径与 mac 逐条对齐】
// · 分带：文件带 / 函数带 / 边界带（mac 的 `.type` 分支是**死代码** ——
////   没有任何节点被赋予该种类，故不移植）。
// · 铺排：带内语义排序 → 等宽网格 → 3 轮重心扫描（行内按邻居 x 重心、列内按邻居 y 重心）。
// · 走线：行隙/带隙通道车道 + Catmull-Rom 平滑；被卡片挡住时绕行。
// · 置信度分数：引擎 confidence.cj 公式的镜像。
// · 热色三档：**契约色**（与 HTML 交付物逐字同色），不是 DS 设计令牌 ——
//   所以不进 DesignTokens，也不许被主题改写。
//
// 【颜色为什么用 rgb() 三元组而不是 #hex】
// 契约色**不是设计令牌**，不该走 DS 那条路；D2 散值门现在盯所有色值形式
// （#hex / QColor 三元组 / rgb() 全都抓），故本文件在 scripts/ci-d2.sh 的
// **显式豁免清单**里逐条登记 —— 豁免是登记出来的，不是「换个写法碰巧躲过」。
#pragma once
#include <QColor>
#include <QHash>
#include <QPointF>
#include <QString>
#include <QVector>
#include "../models/CodeGraph.h"

namespace HeatLayout {

/// 视觉分层。
enum class Layer {
    files = 1,    ///< 文件带
    funcs = 3,    ///< 函数带（符号）
    boundary = 5, ///< 跨作用域边界带
};

/// 一张卡（文件 / 符号 / 跨作用域边界）。
struct Card {
    int node = -1;  ///< arena 索引（-1 = 合成的边界卡）
    QString id;
    QString name;
    QString path;   ///< 所属文件路径（符号卡 = 所在文件；边界卡 = 被引用的文件）
    double x = 0, y = 0, w = 0, h = 0;
    int layerIndex = 0; ///< 第几带
    int rank = 0;       ///< 带内阅读序（= 序号徽标）
    int hue = 0;        ///< 身份色相
    int penalty = 0;    ///< 子树疑点权重和（热色的输入）
    GraphNodeKind kind = GraphNodeKind::sym; ///< 节点种类（决定尺寸与分层）
    int declLine = 0;   ///< 符号的声明行（带内排序用）
    bool boundary = false; ///< 合成的跨作用域边界卡
};

/// 一条边（文件级引用边 / 符号级调用边）。
struct Edge {
    QString from, to;
    int w = 1;
    QString tier = QStringLiteral("resolved"); ///< resolved / guessed（guessed 画虚线）
};

/// 一条走线（折线 waypoint + Catmull-Rom 采样）。
struct Route {
    QString from, to;
    int w = 1;
    QString tier;
    QVector<QPointF> points;   ///< 折线 waypoint
    QVector<QPointF> smoothed; ///< Catmull-Rom 采样
};

/// 置信度分数（引擎 confidence.cj 公式的镜像）。
int confScore(int penalty, int files);

/// 热色三档（契约色，与 HTML confidenceColor 逐字同色）。
QColor heatColor(int score);

/// 身份色（黄金角色相 + 明暗交替）。
QColor idColor(int hue);

/// ── 热力图画布配色（深色画布专属：这一套色只服务热力图）──
/// ⚠ **为什么不在 DS**：DS 是通用设计令牌（表面/文字/语义色），而这套是
///   「热力图这个组件的一套配色」——把它塞进 DS 会让 DS 变成杂物袋。
///   ⚠ **为什么在判定层**：热力图本来就有色职责（heatColor/idColor），
///   画布色跟着住这儿 = 这个组件的色**只有一个出处**（原来散在
///   HeatmapWidget 的 7 处，改一处配色要翻 7 个地方）。
namespace Canvas {
QColor cardBase();  ///< 卡底（深蓝底）
QColor cardText();  ///< 卡片主文字
QColor cardLabel(); ///< 卡片次级标签（文件/符号）
QColor cardNote();  ///< 卡片注释（跨作用域引用）
QColor stroke();    ///< 描边 / 节点头点
} // namespace Canvas

/// 身份色相分配（黄金角 137.508°，按节点 id 字典序）——与 HTML 的 HUE_OF 同口径。
QHash<QString, int> huesFor(const CodeGraph &g);

/// 当前层级应铺排的卡。
/// @param drillNode 下钻到的文件（arena 索引；-1 = 文件层）。
/// 文件层 = 全部文件；下钻层 = 该文件的符号 + 跨作用域边界卡（最多 9 张，溢出并成「+N」）。
QVector<Card> scopeCards(const CodeGraph &g, const QHash<QString, int> &hues, int drillNode,
    const QVector<Edge> &symEdges);

/// 当前层级的边集。
/// 文件层 = 文件级引用边（映射成「f:路径」节点 id）；下钻层 = 作用域内的符号级调用边（同对聚合）。
QVector<Edge> scopeEdges(const CodeGraph &g, const QVector<Edge> &symEdges,
    const QVector<GraphFileEdge> &fileEdges, int drillNode);

/// 铺排：分带 + 等宽网格 + 重心扫描。
QVector<Card> layout(const QVector<Card> &nodes, const QVector<Edge> &edges, double width,
    double height);

/// 走线：通道车道 + Catmull-Rom。
QVector<Route> routes(const QVector<Card> &cards, const QVector<Edge> &edges);

/// Catmull-Rom 采样（折线 waypoint → 平滑曲线密集点）。
QVector<QPointF> catmull(const QVector<QPointF> &pts, int per);

} // namespace HeatLayout
