// GraphScene.h — moongit-graph-scene v1 契约模型（引擎 docs/graph-scene-schema.md）。
//
// 【两层契约】
// · 渲染契约 = 标准 Canvas2D API 的可审计子集（见 platform/Canvas2D.h）；
// · 数据契约 = 场景 JSON（本文件）。
// 数据单来源：换渲染栈数据零改动（章程 §3.5 平台 Canvas 分派）。
//
// 【红线】
// · `v` 必须是 1：契约版本不认识就明说，**不做静默兼容**（mac GraphScene.swift 同款纪律）。
// · 三个恒发字段必须能读出「有值」与「零」的区别，缺键 = 契约过旧（不许回落成 0）：
//   views.*.edgesDropped（被丢弃的边数，0 也发）、meta.warnings（违规/环的计数与模块对，
//   空也发）、meta.chips[].count（**数字**字段，布局/汇总一律读它，不许从 label 抠数字）。
// · 未知 shape 类型不许静默跳过：进 unknown 计数，由调用方披露。
#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QString>
#include <QStringList>
#include <QVector>
#include <optional>

// ── 形状（t: frame|rrect|rect|text|edge）──
struct GraphShape {
    QString type;
    double x = 0, y = 0, w = 0, h = 0, r = 0;
    QString text;
    QString label; // frame 的层框标题（引擎用 label 键，不是 text）
    QString color; // token
    QString fill;  // token
    QString stroke; // token
    QString align;  // text: left|center|right
    QString node;   // 归属节点 id
    double size = 0, weight = 400, maxw = 0;
    double sw = 0;   // stroke width
    double alpha = 1.0;
    double arrow = 0;
    double delay = 0;
    QVector<double> points; // edge 的 p（8 数：x1,y1,cx1,cy1,cx2,cy2,x2,y2）
    QString c0, c1;          // edge 两端颜色 token
    QStringList edge;        // edge 两端节点 id

    static GraphShape fromJson(const QJsonObject &o);
};

// ── 命中区（点击下钻）──
struct GraphHit {
    QString id;
    double x = 0, y = 0, w = 0, h = 0;
    QString drill; // 下钻目标 view id
    QString jump;  // 跳转目标 view id
    static GraphHit fromJson(const QJsonObject &o);
};

// ── 粒子（边的流动相位）──
struct GraphParticle {
    QVector<double> p; // 8 数
    int n = 0;         // 该组粒子数（引擎发的数字）
    double sp = 0;     // 相位推进速度
    QString color;     // token
    static GraphParticle fromJson(const QJsonObject &o);
};

// ── 视图（arch 与 module:*）──
struct GraphView {
    QString id, label, parent;
    QMap<QString, QString> nodeTheme; // node:<id> 二跳的第一跳
    QVector<GraphShape> shapes;
    QVector<GraphParticle> particles;
    QVector<GraphHit> hits;
    int edgesDropped = 0; // 恒发：被丢弃的边数（0 也发）
    double bx0 = 0, by0 = 0, bx1 = 0, by1 = 0; // 内容包围盒

    static GraphView fromJson(const QString &id, const QJsonObject &o);
};

// ── 主题 token 表 ──
struct GraphThemeTokens {
    QMap<QString, QString> simple; // text/muted/bg0/…（非数组非字典的直取值）
    QStringList cols;               // cols.N
    QStringList fills;              // fills.N
    QMap<QString, QString> langs;   // langs.<lang>

    static GraphThemeTokens fromJson(const QJsonObject &o);
};

// ── 违规与环（恒发，空也发）──
struct GraphWarnings {
    int violations = 0;
    int cycleEdges = 0;
    QStringList violationPairs;
    QStringList cycleModules;
    static GraphWarnings fromJson(const QJsonObject &o);
};

// ── 分层条目（count 是数字字段）──
struct GraphChip {
    int layer = 0;
    int count = 0;
    QString label;
    static GraphChip fromJson(const QJsonObject &o);
};

// ── 场景 ──
struct GraphScene {
    int v = 0;
    QString gen;
    QString title, sub, stats, hint, root, search, fit, themeBtn;
    bool truncated = false;
    GraphWarnings warnings;
    QVector<GraphChip> chips;
    QJsonObject panelMeta; // meta.panel（侧栏文案）
    GraphThemeTokens dark, light;
    QVector<GraphView> views;             // arch 恒排第一，其余按引擎导出顺序
    QMap<QString, QJsonObject> panels;   // "<view>:<node>" → 侧栏数据

    /// 解析。返回 nullopt = 契约不认（版本不对 / 必发键缺）。
    static std::optional<GraphScene> fromJson(const QJsonObject &o);

    const GraphView *view(const QString &id) const;
    bool hasView(const QString &id) const { return view(id) != nullptr; }
};
