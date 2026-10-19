// IndexStatus.h — 持久化代码索引的状态判定层（纯函数，零 QWidget 头）。
//
// 【为什么值得接】
// 代码图谱页的「生成」按钮写的是引擎的**持久化索引**（`index gen`），
// 但页头概览读的是**实时扫描**（`graph overview`）—— 两套数据源。
// 结果是：用户点完「生成」**看不到任何变化**（索引写进去了，界面没读它），
// 按钮形同虚设，用户只会以为坏了。
// 本层把索引自己的状态显性化：代数、节点/边数、探针时间、落盘路径。
//
// 【三处容易错得毫无声响的口径】
//   ① **`fresh` 与 `rebuilt` 不是一回事**：
//      `fresh: true` = 源文件没动（索引已最新，**什么都没重建**）；
//      `fresh: false` = 源文件变了，索引被**重建**（`rebuilt: true`）。
//      把「已最新」说成「已更新」会让用户以为索引刷过了（其实没有新内容）。
//   ② **`rebuilt` 在 `fresh: true` 时引擎不发这个键** —— 按 `false` 读会把
//      「没重建」说成「没重建过」（后者是历史事实，前者是这次的状态）。
//      故有 `rebuiltPresent` 标志。
//   ③ **缺字段不回落成 0**：`nodes: 0` 与「引擎没发 nodes」是两件事
//      （空索引 vs 契约漂移）。计数一律 -1 哨兵 + present 标志。
#pragma once
#include <QJsonObject>
#include <QMap>
#include <QString>

namespace IndexStatus {

/// 索引概览（引擎 `index overview --json`）。
struct Overview {
    bool ok = false; ///< 载荷形状对不对（不是「索引有没有内容」！）
    QString error;
    QString project;
    int updateCount = -1;    ///< 索引代数（第几次生成/重建；-1 = 引擎没发）
    QString generatedAt;     ///< 生成时间（引擎给的 ISO8601 原文）
    bool selfHealed = false; ///< 引擎是否自愈过（索引过期时自动重建）
    bool selfHealedPresent = false; ///< 引擎有没有发这个键
    int nodes = -1;          ///< 符号节点数（-1 = 没发；0 是合法值）
    int edges = -1;          ///< 调用边数（-1 = 没发）
    int files = -1;          ///< 收录文件数（-1 = 没发）
    QMap<QString, int> byKind; ///< 按符号种类计数
    int probeFiles = -1;       ///< 探针扫到的文件数
    qint64 probeBytes = -1;    ///< 探针扫到的字节数
    qint64 probeMaxMtime = -1; ///< 探针见到的最大 mtime（毫秒）

    bool hasUpdateCount() const { return updateCount >= 0; }
    bool hasNodes() const { return nodes >= 0; }
    bool hasEdges() const { return edges >= 0; }
    bool hasFiles() const { return files >= 0; }
};

/// 增量更新的结果（引擎 `index update --json`）。
struct UpdateResult {
    bool ok = false;
    QString error;
    QString project;
    bool fresh = false;        ///< 源状态没动（索引已最新）
    bool rebuilt = false;      ///< 索引被重建
    bool rebuiltPresent = false; ///< 引擎有没有发 rebuilt（fresh 时不发）
    int updateCount = -1;      ///< 索引代数
    QString generatedAt;       ///< 生成时间
    QString indexJsonPath;     ///< 落盘的 index.json 绝对路径（fresh 时没有）

    bool hasUpdateCount() const { return updateCount >= 0; }
};

/// 解析 `index overview --json` 的载荷。
Overview parseOverview(const QJsonObject &o);

/// 解析 `index update --json` 的载荷。
UpdateResult parseUpdate(const QJsonObject &o);

/// 一行索引摘要（如「索引：3 符号 · 1 边 · 第 1 代」）。
/// 缺项不占位（不写「0 符号」这种会误导的文案）。
QString summary(const Overview &o);

} // namespace IndexStatus
