// AutostartManager.h — 开机自启（mac SMAppService 的 Linux 等价物：XDG Autostart）。
//
// 开关 = 写/删 ~/.config/autostart/cn.deepdolphin.app.desktop（内容以已安装 desktop 为底，
// Exec=<applicationFilePath()> 绝对路径）；isEnabled 查文件存在且
// X-deepDolphin-Autostart-enabled 不为 false。失败由调用方回滚开关（logic/ClientDecisions）。
#pragma once
#include <QString>

class AutostartManager {
public:
    static QString desktopFilePath(); // ~/.config/autostart/cn.deepdolphin.app.desktop
    static bool isEnabled();
    // 写/删 autostart 文件；失败时 errOut 给出原因（调用方回滚开关 + 红字）。
    static bool setEnabled(bool enabled, QString *errOut);
};
