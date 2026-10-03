// ShortcutMap.h — 快捷键的唯一声明处（纯函数层，零 GUI 依赖；mac ShortcutMap.swift 对位）。
//
// mac → deepin 映射（PLAN §6.3）：
//   ⌘R→Ctrl+R 刷新 · ⇧⌘U→Ctrl+Shift+U 浅更新 · ⌥⇧⌘D→Ctrl+Alt+Shift+D 深更新
//   ⌘.→Ctrl+. 停止更新 · ⌘F→Ctrl+F 聚焦搜索 · ⌘,→Ctrl+, 设置 · ⌘W→Ctrl+W 关面板
//   ⌘1/2/3→Ctrl+1/2/3 视图 · ⌘4→Ctrl+4 打开当前选中项目 · ⌘↩→Ctrl+Return Agent 发送
//
// ⚠️ 深更新**必须真绑**（mac 曾声明未绑定是真缺陷）；Ctrl+Shift+U 可能与输入法
// Unicode 输入冲突——实测后如冲突保持绑定并在菜单显示实际序列（PLAN §8 T10）。
#pragma once
#include <QKeySequence>
#include <QVector>
#include <algorithm>

struct ShortcutSpec {
    QKeySequence seq;
    QString actionId; // 稳定动作 id（绑定/测试判据）
    QString display;  // 展示串（文档与测试用；菜单显示按 Qt 自动生成为准——平台差异已记录）
};

namespace ShortcutMap {

// 固定视图顺序（数组长度 = Ctrl+N 的上界；没有 Ctrl+5——硬凑只会让用户按了没反应）
inline QVector<QString> viewOrder()
{
    return { QStringLiteral("dashboard"), QStringLiteral("board"), QStringLiteral("milestones") };
}

// 全表。viewOrderLen 可传入以便测试（缺省 3 = 固定三视图）。
// ⚠️ Ctrl+4（打开当前选中项目）在 all 表里但**不在 viewOrder**（动态项目详情）
// ——漏了它，任何与 Ctrl+4 撞车的声明都查不出来（mac 负控 NC67-d 的教训）。
inline QVector<ShortcutSpec> shortcutMap(int viewOrderLen = 3)
{
    QVector<ShortcutSpec> m = {
        { QKeySequence(QStringLiteral("Ctrl+R")), QStringLiteral("refresh"), QStringLiteral("Ctrl+R") },
        { QKeySequence(QStringLiteral("Ctrl+Shift+U")), QStringLiteral("shallowUpdate"),
            QStringLiteral("Ctrl+Shift+U") },
        { QKeySequence(QStringLiteral("Ctrl+Alt+Shift+D")), QStringLiteral("deepUpdate"),
            QStringLiteral("Ctrl+Alt+Shift+D") },
        { QKeySequence(QStringLiteral("Ctrl+.")), QStringLiteral("stopUpdate"), QStringLiteral("Ctrl+.") },
        { QKeySequence(QStringLiteral("Ctrl+F")), QStringLiteral("focusSearch"), QStringLiteral("Ctrl+F") },
        { QKeySequence(QStringLiteral("Ctrl+,")), QStringLiteral("settings"), QStringLiteral("Ctrl+,") },
        { QKeySequence(QStringLiteral("Ctrl+W")), QStringLiteral("closePanel"), QStringLiteral("Ctrl+W") },
    };
    // Ctrl+1..N 视图切换（固定视图数就是上界，不硬凑 Ctrl+5）
    static const char *kKeys[] = { "Ctrl+1", "Ctrl+2", "Ctrl+3", "Ctrl+4" };
    const int n = qBound(0, viewOrderLen, 3);
    for (int i = 0; i < n; ++i) {
        m.append({ QKeySequence(QLatin1String(kKeys[i])), QStringLiteral("view:%1").arg(viewOrder().at(i)),
            QLatin1String(kKeys[i]) });
    }
    m.append({ QKeySequence(QStringLiteral("Ctrl+4")), QStringLiteral("view:currentProject"),
        QStringLiteral("Ctrl+4") });
    return m;
}

// 键位是否重复（QKeySequence 相等即视为冲突——修饰符顺序 Qt 已归一）
inline bool hasDuplicate(const QVector<ShortcutSpec> &map)
{
    for (int i = 0; i < map.size(); ++i) {
        for (int j = i + 1; j < map.size(); ++j) {
            if (map.at(i).seq == map.at(j).seq && map.at(i).seq != QKeySequence())
                return true;
        }
    }
    return false;
}

inline const ShortcutSpec *find(const QVector<ShortcutSpec> &map, const QString &actionId)
{
    const auto it = std::find_if(map.cbegin(), map.cend(),
        [&](const ShortcutSpec &s) { return s.actionId == actionId; });
    return it == map.cend() ? nullptr : &(*it);
}

} // namespace ShortcutMap
