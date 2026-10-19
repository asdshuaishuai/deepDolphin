// IconNames.h — 图标候选链的**唯一出处**（判定层：纯数据、零 UI 依赖）。
//
// 【为什么要有它】
//   M1-2 之前，图标名散在 11 处 UI 代码里（`QIcon::fromTheme("list-add")` 这种），
//   每处各写一个名字 ⇒ ① 图标主题换名时**要改 11 个地方**；② 某个名字在主题里
//   解析不到时，界面**静默变成空图标**，没人知道是哪个名字没的。
//   ⇒ 收敛成「**逻辑图标名** → **候选名链**（有序，第一个解析成功即用）」：
//   UI 只说「我要 add 这个图标」，具体叫什么由本表说了算。
//
// 【为什么是枚举而不是字符串】
//   字符串拼错是**编译期发现不了**的运行时事故（图标空掉，界面还「看着没事」）。
//   用 `enum class Id` ⇒ 拼错**编译不过**；漏登记 ⇒ 判据红（表与枚举必须严格一一对应）。
//
// 【候选链怎么排】
//   ① **当前在用的主题名**（视觉不变：链是「多几条路」，不是「换个图标」）；
//   ② 同义的 **-symbolic** 变体（最小主题只有 symbolic 时命中）；
//   ③ **同义通用名**（freedesktop 通用名，兜底）。
//   ⇒ 链里必须**有替代项**：只写一个名字的链在缺那个名字的主题上就是空图标。
//
// 【DDci 优先】
//   候选名的解析顺序（DDci → 主题 → qrc 染色）在**执行层**
//   （`platform/IconResolver.h`）；本表只管「有哪些名字、按什么顺序」。
#pragma once

#include <QList>
#include <QString>
#include <QStringList>

namespace IconNames {

/// 逻辑图标（**唯一**的可引用形式；拼错编译不过）。
enum class Id {
    // 侧栏与视图行
    add,
    dashboard,
    board,
    milestone,
    // 设置窗三页签
    settings,
    automation,
    ai,
    // 状态与提示
    warning,
    info,
    dataWarning,
    refresh,
    globe,
    // 详情页工具钮
    close,
    copy,
    arch,
    codegraph,
    patch,
    brief,
    report,
    folder,
    folderNew,
    terminal,
    remote,
    // 详情页 git 操作
    gitPull,
    gitPush,
    gitStash,
    gitUnstash,
};

/// 逻辑名 → 候选名链（有序，第一个解析成功即用）。
QStringList fallbacks(Id id);

/// 逻辑名的字符串形式（探针/日志用；**不是**给调用方拼名字用的）。
QString name(Id id);

/// 全部逻辑图标（清单本身；自检与探针据此枚举）。
QList<Id> all();

/// 逻辑名在清单里吗（按字符串查；给「拼错了」的路径用）。
bool isKnown(const QString &logical);

} // namespace IconNames
