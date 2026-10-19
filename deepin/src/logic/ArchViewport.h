// ArchViewport.h — 架构图页的视口与命中判定（纯函数层，零 QWidget 头）。
//
// 【为什么独立成纯函数】
// 视口换算（屏幕↔世界）与命中测试是**最容易悄悄错**的两件事：
// 缩放没跟上下标就会「点不中」；命中区顺序错了就会「选错节点」。
// 两者都不该等到看图才发现 —— 抽成纯函数后可直接在无图形环境里判。
//
// 【坐标约定】screen = world · scale + offset（与 SceneRender 同一套）。
#pragma once
#include <QPointF>
#include <QString>
#include <optional>
#include "../models/GraphScene.h"

namespace ArchViewport {

/// 视口。
struct Viewport {
    double scale = 1.0;
    double offsetX = 0.0;
    double offsetY = 0.0;
};

/// 按视图内容包围盒自适应画布（四周留 pad 像素）。缩放夹在 [0.05, 4]。
/// 包围盒非法（空视图 / 零面积）时给恒等视口，不猜比例。
Viewport fit(const GraphView &v, double width, double height, double pad = 40.0);

/// 屏幕坐标 → 世界坐标。
QPointF toWorld(const Viewport &vp, double screenX, double screenY);

/// 世界坐标 → 屏幕坐标。
QPointF toScreen(const Viewport &vp, double worldX, double worldY);

/// 命中测试：屏幕点落在哪个命中区里。
/// 返回命中的节点 id（空 = 没命中）；契约里 hits 带 drill（下钻目标）——
/// 下钻动作由调用方按 hit.drill 决定，本层只答「命中了谁」。
std::optional<QString> hitAt(const GraphView &v, const Viewport &vp, double screenX, double screenY);

} // namespace ArchViewport
