// TrayBackend.h — 平台层：托盘后端选择的**环境开关**（测试/探针用）。
//
// 【为什么需要它 —— 批 Y 实测逼出来的】
//   DDE 25 上自动选的是 **deepin 托盘窗口协议** ⇒ SNI 那条路**根本不会被走**
//   ⇒ 批 X 那个「IconPixmap 字节级」端到端判据在 DDE 上**永远跑不起来**
//   （SNI 服务不上线 ⇒ 探针假红）。
//   ⇒ 探针要有一个**显式强制**的口子，才能在这台机器上仍然验 SNI 路径。
//
// 【纪律】
//   · 默认**不强制**（= 按平台能力自动选）⇒ 生产行为零变化；
//   · **认不出的值当作「没指定」**（判定层负责解析，平台层不自己判）；
//   · 这是**测试钩子**，不是业务配置 —— 别拿它当功能开关用。
#pragma once

#include "../logic/DeepinTray.h"

namespace platform {

/// 托盘后端的强制指定（读环境变量 `DEEPDOLPHIN_TRAY_BACKEND`）。
///
/// ⚠ 环境变量名只写在这里一处；**怎么解析**归判定层（单一真相源）。
///   没设 / 空 / 认不出 ⇒ `nullopt`（= 按平台能力自动选）。
TraySni::BackendOverride trayBackendOverride();

} // namespace platform
