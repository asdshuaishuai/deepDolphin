// DeepinTray.cpp — deepin 托盘窗口协议的判定层实现（纯结论）。
#include "DeepinTray.h"

namespace TraySni {

BackendOverride parseBackendOverride(const QString &text)
{
    // ⚠ 认不出的字样 ⇒ `nullopt`（按平台能力自动选），**不**静默落到某个后端。
    const QString t = text.trimmed().toLower();
    if (t == QLatin1String("sni"))
        return Backend::Sni;
    if (t == QLatin1String("deepin"))
        return Backend::DeepinWindow;
    if (t == QLatin1String("none"))
        return Backend::None;
    return BackendOverride{};
}

Backend chooseBackend(bool deepinSelectionPresent, bool watcherPresent, BackendOverride forced)
{
    // ⚠ 强制指定（测试/探针用）**优先于**自动选择 ——
    //   否则探针在本机上想验的那条路根本走不到（判据就成了永远红的假判据）。
    if (forced.has_value())
        return *forced;

    // ⚠ 顺序**有讲究**：deepin 选区优先。
    //   DDE 25 上 SNI watcher 也在（ayatana 变体）但**不画** SNI 图标；
    //   若「有 watcher 就走 SNI」，图标永远不出现（这正是批 X 踩的坑）。
    if (deepinSelectionPresent) {
        return Backend::DeepinWindow;
    }
    if (watcherPresent) {
        return Backend::Sni;
    }
    return Backend::None;
}

QString backendName(Backend backend)
{
    switch (backend) {
    case Backend::Sni:
        return QStringLiteral("sni");
    case Backend::DeepinWindow:
        return QStringLiteral("deepin-window");
    case Backend::None:
        break;
    }
    return QStringLiteral("none");
}

} // namespace TraySni
