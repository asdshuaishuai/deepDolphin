// CommitTypeComposition.h — 提交构成的切片/摘要/色板（mac CommitTypeComposition.swift 对位）。
//
// 【红线】色板容量 12 ≥ 引擎 COMMIT_TYPE_ORDER 长度；**容量外不取模**
// （第 13 类拿到第 1 类颜色 = 两类糊成一类）。两轴截断彼此独立：
//   · sampleTruncated —— 引擎的采样窗口（commitTypesTruncated）
//   · 界面自己砍条数   —— 必须由界面自己披露
#pragma once
#include <QColor>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QPair>
#include <vector>

class CommitTypeStat;

namespace CommitTypes {

constexpr int PULSE_LINE_MAX = 5; // 脉冲行里最多列几种（唯一来源）。不叫 LINE_MAX——
                                  // glibc limits.h 已有同名宏，撞名会炸编译
constexpr int PALETTE_CAPACITY = 12;

// 序列色：排名序号 → 颜色。**全局唯一映射口**（分段条/图例/语言分布共用）。
// i ≥ 容量时返回无效 QColor（调用方必须先按 capacity 切片，不许取模）。
QColor sequenceColor(int i);

struct Slice {
    QVector<QPair<QString, int>> rows; // 容量内切片
    int total = 0;                     // 引擎一共给了几种
    bool cut = false;                  // 有类型因色板容量被挡在卡片外
    QString note;                      // 空串 = 没什么要说的
};

// 提交构成卡片的可见切片：色板画不完的条数**说出来**，不靠取模。
Slice cardSlice(const QVector<QPair<QString, int>> &entries);

// 按提交类型筛选（空 = 全部）。只作用于堆叠条/图例。
QVector<QPair<QString, int>> filtered(const QVector<QPair<QString, int>> &entries,
    const QString &typeFilter);

// 脉冲行的一行摘要；空串 = 压根没有提交类型可列。
// 两条披露轴独立：样本截断（「近 X/Y 条样本」或「样本，非全量」）+ 行内截断
//（「本行只列前 N 种，共 M 种，完整构成见「提交构成」卡片」）。
QString lineFor(const QVector<QPair<QString, int>> &entries, bool sampleTruncated, int totalCommits);

// 引擎条目 → (type,count) 对。
QVector<QPair<QString, int>> toEntries(const std::vector<CommitTypeStat> &stats);

} // namespace CommitTypes
