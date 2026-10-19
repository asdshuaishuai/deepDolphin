// IconNames.cpp — 图标候选链表（判定层）。
//
// ⚠ **链里不许只写一个名字**：主题缺那个名字时界面会静默变成空图标，
//   而「哪个图标没解析到」是**说不出来**的（空门）。⇒ 每条链至少两个候选。
// ⚠ 每个链的**第一个候选 = 该图标今天实际在用的主题名** —— 收敛是为了
//   「缺名时有路走 + 缺失看得见」，**不是为了换图标**（视觉不该因此变）。
#include "IconNames.h"

#include <QHash>

namespace {
/// 逻辑图标 → 候选链。**顺序即优先级**（第一个解析成功即用）。
const QHash<IconNames::Id, QStringList> &table()
{
    using I = IconNames::Id;
    static const QHash<I, QStringList> kTable = {
        // ── 侧栏与视图行 ─────────────────────────────────────────
        { I::add, { QStringLiteral("list-add"), QStringLiteral("add"),
            QStringLiteral("list-add-symbolic") } },
        { I::dashboard, { QStringLiteral("preferences-desktop-wallpaper"),
            QStringLiteral("dashboard"), QStringLiteral("view-grid-symbolic") } },
        { I::board, { QStringLiteral("view-list-details"), QStringLiteral("board"),
            QStringLiteral("view-list-details-symbolic") } },
        { I::milestone, { QStringLiteral("flag"), QStringLiteral("dd-milestone"),
            QStringLiteral("flag-symbolic") } },
        // ── 设置窗三页签 ─────────────────────────────────────────
        { I::settings, { QStringLiteral("preferences-system"),
            QStringLiteral("preferences-system-symbolic"), QStringLiteral("settings") } },
        { I::automation, { QStringLiteral("preferences-system-time"),
            QStringLiteral("preferences-system-time-symbolic"), QStringLiteral("preferences-other"),
            QStringLiteral("configuration") } },
        { I::ai, { QStringLiteral("applications-engineering"), QStringLiteral("dd-ai"),
            QStringLiteral("applications-engineering-symbolic"), QStringLiteral("starred") } },
        // ── 状态与提示 ───────────────────────────────────────────
        { I::warning, { QStringLiteral("dialog-warning"), QStringLiteral("dd-warning"),
            QStringLiteral("dialog-warning-symbolic") } },
        { I::info, { QStringLiteral("dialog-information"),
            QStringLiteral("dialog-information-symbolic"), QStringLiteral("information") } },
        { I::dataWarning, { QStringLiteral("data-warning"), QStringLiteral("dialog-warning"),
            QStringLiteral("dialog-warning-symbolic") } },
        { I::refresh, { QStringLiteral("view-refresh"),
            QStringLiteral("view-refresh-symbolic"), QStringLiteral("refresh") } },
        { I::globe, { QStringLiteral("globe"), QStringLiteral("web-browser"),
            QStringLiteral("web-browser-symbolic") } },
        // ── 详情页工具钮 ─────────────────────────────────────────
        { I::close, { QStringLiteral("window-close"),
            QStringLiteral("window-close-symbolic"), QStringLiteral("dialog-cancel") } },
        { I::copy, { QStringLiteral("edit-copy"),
            QStringLiteral("edit-copy-symbolic"), QStringLiteral("edit-paste") } },
        { I::arch, { QStringLiteral("view-tree"), QStringLiteral("view-list-tree"),
            QStringLiteral("format-justify-fill") } },
        { I::codegraph, { QStringLiteral("system-search"),
            QStringLiteral("system-search-symbolic"), QStringLiteral("edit-find") } },
        { I::patch, { QStringLiteral("utilities-diagnose"),
            QStringLiteral("utilities-diagnose-symbolic"), QStringLiteral("utilities-system-monitor") } },
        { I::brief, { QStringLiteral("applications-utilities"),
            QStringLiteral("applications-utilities-symbolic"), QStringLiteral("documentation") } },
        { I::report, { QStringLiteral("document-save"),
            QStringLiteral("document-save-symbolic"), QStringLiteral("document-export") } },
        { I::folder, { QStringLiteral("folder"),
            QStringLiteral("folder-symbolic"), QStringLiteral("folder-open") } },
        { I::folderNew, { QStringLiteral("folder-new"), QStringLiteral("folder"),
            QStringLiteral("folder-symbolic") } },
        { I::terminal, { QStringLiteral("utilities-terminal"),
            QStringLiteral("utilities-terminal-symbolic"), QStringLiteral("terminal") } },
        { I::remote, { QStringLiteral("web-browser"),
            QStringLiteral("web-browser-symbolic"), QStringLiteral("network-workgroup") } },
        // ── 详情页 git 操作 ──────────────────────────────────────
        { I::gitPull, { QStringLiteral("arrow-down"), QStringLiteral("go-down"),
            QStringLiteral("arrow-down-symbolic") } },
        { I::gitPush, { QStringLiteral("arrow-up"), QStringLiteral("go-up"),
            QStringLiteral("arrow-up-symbolic") } },
        { I::gitStash, { QStringLiteral("archive-insert"),
            QStringLiteral("archive-insert-symbolic"), QStringLiteral("archive-remove") } },
        { I::gitUnstash, { QStringLiteral("archive-insert-axis"),
            QStringLiteral("archive-insert"), QStringLiteral("archive-insert-symbolic") } },
    };
    return kTable;
}

/// 逻辑名（字符串）↔ 枚举的一一映射（表与枚举必须严格相等）。
const QHash<IconNames::Id, QString> &nameTable()
{
    using I = IconNames::Id;
    static const QHash<I, QString> kNames = {
        { I::add, QStringLiteral("add") },
        { I::dashboard, QStringLiteral("dashboard") },
        { I::board, QStringLiteral("board") },
        { I::milestone, QStringLiteral("milestone") },
        { I::settings, QStringLiteral("settings") },
        { I::automation, QStringLiteral("automation") },
        { I::ai, QStringLiteral("ai") },
        { I::warning, QStringLiteral("warning") },
        { I::info, QStringLiteral("info") },
        { I::dataWarning, QStringLiteral("dataWarning") },
        { I::refresh, QStringLiteral("refresh") },
        { I::globe, QStringLiteral("globe") },
        { I::close, QStringLiteral("close") },
        { I::copy, QStringLiteral("copy") },
        { I::arch, QStringLiteral("arch") },
        { I::codegraph, QStringLiteral("codegraph") },
        { I::patch, QStringLiteral("patch") },
        { I::brief, QStringLiteral("brief") },
        { I::report, QStringLiteral("report") },
        { I::folder, QStringLiteral("folder") },
        { I::folderNew, QStringLiteral("folderNew") },
        { I::terminal, QStringLiteral("terminal") },
        { I::remote, QStringLiteral("remote") },
        { I::gitPull, QStringLiteral("gitPull") },
        { I::gitPush, QStringLiteral("gitPush") },
        { I::gitStash, QStringLiteral("gitStash") },
        { I::gitUnstash, QStringLiteral("gitUnstash") },
    };
    return kNames;
}
} // namespace

namespace IconNames {

QStringList fallbacks(Id id)
{
    return table().value(id);
}

QString name(Id id)
{
    return nameTable().value(id);
}

QList<Id> all()
{
    // 按枚举声明序返回（清单顺序稳定 ⇒ 探针输出可比对）。
    return { Id::add, Id::dashboard, Id::board, Id::milestone,
        Id::settings, Id::automation, Id::ai,
        Id::warning, Id::info, Id::dataWarning, Id::refresh, Id::globe,
        Id::close, Id::copy, Id::arch, Id::codegraph, Id::patch, Id::brief, Id::report,
        Id::folder, Id::folderNew, Id::terminal, Id::remote,
        Id::gitPull, Id::gitPush, Id::gitStash, Id::gitUnstash };
}

bool isKnown(const QString &logical)
{
    return nameTable().values().contains(logical);
}

} // namespace IconNames
