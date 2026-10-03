// Route.h — 启动参数 → 路由意图。**纯函数层，零 GUI 依赖**（mac Route.swift 对位）。
//
// 深链参数**各自独立**生效，任何一个开关都不该被另一个无关开关挡住；
// 参数缺失值（`--project` 后面没有名字 / 值以 `--` 开头）当作没给这个参数。
#pragma once
#include <QString>
#include <QStringList>
#include <optional>

// 深链解析出的意图。**解析一次**，之后界面只读结果。
// 各开关可并存：`--open-settings --project foo` 同时出现是合法的。
struct LaunchRoute {
    bool openPanel = false;      // --open-panel（Linux 上主面板本就随启动打开；保留语义）
    QString project;             // --project <名>；空 = 没给
    QString section;             // --section <名>；空 = 没给（dashboard|board|milestones）
    bool openSettings = false;   // --open-settings
    bool openScan = false;       // --scan（desktop Action「扫描项目」：打开添加/扫描面板）
    bool agentSelftest = false;  // --agent-selftest [问题]（AI 阶段实现）
    QString selftestQuestion;    // 自测问句（缺省句见 Route::defaultSelfTestQuestion）
    std::optional<QString> notice;
    std::optional<QString> path; // 位置参数（desktop 项 %f：在面板中打开某个目录）；空 = 没给 // 路由改道说明（Router 阶段写入，详情区顶部深链说明条）
};

namespace Route {

LaunchRoute parseArgs(const QStringList &args); // args 含程序自身路径（QApplication::arguments() 原样）

// `--section` 取值归一：milestones/board/dashboard 之外一律落 dashboard（默认视图）
QString resolveSection(const QString &raw);

// `--agent-selftest` 没带问句时的缺省问句（与 mac 保持一致）
QString defaultSelfTestQuestion();

// 取 `--flag` 后面那个值；值本身是 flag 或不存在 → 不给（nullopt）。
// `--project --open-panel` 里的 --open-panel 是开关不是项目名。
std::optional<QString> flagValue(const QString &flag, const QStringList &args);

} // namespace Route
