// SceneRender.h — 把场景（scene JSON）画成一帧 Canvas2D 调用（纯函数层，零 QWidget 头）。
//
// 【职责切分】
// · 本层只决定「画什么、按什么顺序、什么颜色」——把场景数据翻译成 Canvas2D 调用序列；
// · 平台层（platform/Canvas2D）只负责「把调用翻译成 QPainter」；
// · 判定层可挂记录式接收端（logic/CanvasSink）逐条断言调用序列 —— 无需图形环境。
//
// 【坐标】世界坐标 → 屏幕坐标：screen = world · scale + offset（视口）。
// 【时序】nowMs 是动画时钟（毫秒）：边的入场错峰（delay）、虚线流光（dash phase）、
//   粒子相位推进都读它 —— 同一时刻重画必须逐像素一致（引擎保证两次导出逐字节一致）。
#pragma once
#include <QString>
#include "../models/GraphScene.h"
#include "ArchViewport.h"
#include "CanvasSink.h"

namespace SceneRender {

/// 一帧的统计（判据用；也是「未知 shape 类型不许静默跳过」的披露口）。
struct Stats {
    int shapes = 0;      // 处理的 shape 总数
    int drawn = 0;       // 实际画出的
    int unknown = 0;     // **不认识**的 shape 类型（引擎违约，须披露，不静默跳）
    int edges = 0;       // 画出的边
    int edgesPending = 0;// 还没到入场时刻的边（delay 未到）
    int texts = 0;       // 画出的文字
    int particles = 0;   // 画出的粒子
};

/// 画一个视图。
///
/// theme 取 scene.dark / scene.light；token 解析走 GraphToken（四形态 + 二跳）。
/// view 传 &view 自身（node: 二跳要查它的 nodeTheme）。
///
/// 视口类型用 ArchViewport::Viewport（**唯一出处**）—— 渲染与命中必须共用同一个
/// 换算式，两处各写一份 struct 迟早会各自漂移。
Stats render(const GraphScene &scene, const GraphView &view, bool dark,
    const ArchViewport::Viewport &vp, double width, double height, double nowMs, CanvasSink &sink);

} // namespace SceneRender
