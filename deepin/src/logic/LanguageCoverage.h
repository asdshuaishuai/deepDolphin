// LanguageCoverage.h — 语言分布卡的覆盖度披露（mac LanguageCoverage.swift 对位，纯函数层）。
//
// 三种状态必须分开，任何两种合并都会撒谎：
//   · 截断     —— 看了，只留了一部分（引擎 20000 文件上限）
//   · 引擎砍条数 —— 语言条数被引擎上限砍（languagesTopCut）
//   · 卡片自己砍 —— LANG_BAR_MAX=8，界面自己砍的必须自己说
//   · 采集失败 —— 压根没看成（与「项目群没有这些语言」无关；恒发披露）
#pragma once
#include "../models/DashboardData.h"
#include <QColor>
#include <QPair>
#include <QString>
#include <QVector>

namespace LanguageCoverage {

constexpr int LANG_BAR_MAX = 8;

struct Rows {
    QVector<QPair<QString, int>> rows;       // 卡片实际画的条数（≤ LANG_BAR_MAX）
    QVector<QPair<QColor, int>> barData;     // 与 rows 同源色的分段条数据
    QString emptyTitle;                      // 「暂无数据」/「未采集到语言数据」（failed>0 且空）
    QString note;                            // 卡片下方披露；空串 = 没什么要说的
};

Rows coverage(const DashboardData &d);

} // namespace LanguageCoverage
