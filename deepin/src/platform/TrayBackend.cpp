// TrayBackend.cpp — 平台层：托盘后端选择的**环境开关**。
#include "TrayBackend.h"

namespace platform {

TraySni::BackendOverride trayBackendOverride()
{
    // ⚠ 解析规则在判定层（`parseBackendOverride`）—— 平台层只负责**取环境变量**。
    //   没设 ⇒ `qEnvironmentVariable` 返回空串 ⇒ 判定层判成「没指定」⇒ 自动选。
    return TraySni::parseBackendOverride(qEnvironmentVariable("DEEPDOLPHIN_TRAY_BACKEND"));
}

} // namespace platform
