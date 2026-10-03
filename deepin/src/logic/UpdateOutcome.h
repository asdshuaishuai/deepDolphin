// UpdateOutcome.h — 更新结果的三态文案（mac UpdateOutcome.swift 对位，纯函数层）。
//
// 【红线】三条硬规则：
//   · 没说改动就不能说「已刷新」（引擎报了但没变 → 老实说「没有变化」）；
//   · 有备份必须说备份在哪；没有备份不许提备份（新建文件本来就没有旧版本）；
//   · 文件列举有上限（nameMax=2）时必须说还剩几个。
#pragma once
#include "../models/UpdateResult.h"
#include <QString>
#include <QStringList>

namespace UpdateOutcome {

struct Doc {
    QString file;
    bool changed = false;
    bool created = false;
    QString backup; // 恒发；空串 = 确实没有备份（新建/无变化/dry-run），不是「不知道」
};

// 单项目 shallow/deep 结果 → 文档结果列表（DocChange → Doc）。
QVector<Doc> docsOf(const UpdateResultBase &r);

// 通知/结果面板那一行该说什么。三态：没报文档 / 报了没变 / 真动了。
QString summary(const QVector<Doc> &docs, const QString &project, int nameMax = 2);

// 便捷重载：直接吃 UpdateResultBase。
QString summary(const UpdateResultBase &r, int nameMax = 2);

} // namespace UpdateOutcome
