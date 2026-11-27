// DdePanel.h — DDE 面板几何的**取数层**（平台层：读 D-Bus）。
//
// 【为什么不是自己算】
//   批 V 的任务栏几何是「QPA 可用区与整屏的差值」——**推算**的。
//   DDE 面板**自己**报几何（D-Bus）⇒ 不用猜。
//   实测（本机 deepin / dde-shell 2.0.52）：
//     · 服务名 `org.deepin.ds.Dock`（新）/ `org.deepin.dde.Dock1` /
//       `org.deepin.dde.daemon.Dock1`（旧），三者等价；
//     · 接口 `org.deepin.dde.Dock1`，属性 `geometry`（QRect，只读）
//       与 `position`（int：0=上 1=右 2=下 3=左，**只有新服务有**）；
//     · 本机 geometry = (0,1039,1920,41)、position = 2（下）。
//
// 【为什么是异步读 + 缓存】
//   D-Bus 的属性读是**同步往返**。放在「用户点托盘」的那一刻读，
//   万一面板服务卡住，GUI 线程就跟着卡（面板服务在 DDE 上是壳的一部分，
//   卡住概率低但不是零）⇒ 读放在 worker 线程，结果回 GUI 线程存缓存。
//   ⚠ 代价：弹窗用的是**上一次**读到的值（面板挪边后第一次弹可能偏）。
//   ——面板挪边是低频动作，这个代价可接受；卡 GUI 不可接受。
#pragma once

#include "../logic/PanelGeometry.h"

namespace platform {

/// DDE 面板（取数层；命名空间与文件名同名，调用处读起来不绕）。
namespace DdePanel {

/// 面板真几何（**缓存值**；服务缺席或读失败 ⇒ 无效面板）。
PanelGeometry::Panel current();

/// 同步读一次（**会阻塞**，最多 2s）。
/// ⚠ 只给「一次性、无交互」的场景用（无头探针）；交互路径用 refreshAsync()。
PanelGeometry::Panel readNow();

/// 异步刷新缓存（worker 线程读，结果回 GUI 线程）。
void refreshAsync();

/// 面板服务在不在（只探服务名，不读属性 —— 快）。
bool servicePresent();

} // namespace DdePanel

} // namespace platform
