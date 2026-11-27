// PanelGeometry.h — DDE 面板几何的**判定层**（纯函数、零 UI/零 DBus 依赖）。
//
// 【为什么要有它】
//   批 V 把任务栏几何做成「QPA 可用区与整屏的差值」——**推算**出来的。
//   批 W 查出更硬的真相源：DDE 面板**自己**报几何（D-Bus `org.deepin.ds.Dock`
//   的 `geometry` + `position`）⇒ 不必猜。
//   而「面板在哪条边、占多厚、扣掉后还剩哪块可用区」是**纯几何**，
//   放判定层 ⇒ 可离线测（面板缺席/面板在四边/面板比屏还大……）。
//
// 【为什么单列一个文件而不是并进 logic/Backend】
//   `logic/Backend` 管的是「后端差异」（X11/Wayland 的行为差异）；
//   这里管的是「面板在哪、可用区多大」——两件事的**输入来源不同**
//   （前者来自 QPA 插件名，后者来自面板 D-Bus），分开才不会互相顶替。
//
// 【实测得来的事实（本机 deepin，dde-shell 2.0.52）——】
//   · 面板服务名有三个等价入口：`org.deepin.ds.Dock`（新）、
//     `org.deepin.dde.Dock1`、`org.deepin.dde.daemon.Dock1`（旧）；
//   · 接口 `org.deepin.dde.Dock1`，属性 `geometry`（QRect，只读）与
//     `position`（int：0=上 1=右 2=下 3=左；**只有新服务名有** position）；
//   · 本机实测 geometry = (0, 1039, 1920, 41)、position = 2（下），
//     与 QPA 的 availableGeometry 扣出来的边距**完全一致**（0,0,0,41）。
#pragma once

#include <QRect>
#include <QString>

namespace PanelGeometry {

/// 面板所在边（dde-shell 的 Position 枚举）。
enum class Edge {
    Unknown, ///< 位置读不出来（或不认识的值）⇒ 只能按「贴着哪条边」猜
    Top,
    Right,
    Bottom,
    Left,
};

/// 面板位置枚举 → 边。
/// ⚠ **别的值一律 Unknown**：猜错边 ⇒ 弹窗跑到屏幕另一边，比不猜更糟。
///   （0=上 1=右 2=下 3=左，实测 position=2 ⇒ Bottom。）
Edge edgeFromPosition(int position);

/// 边的字符串形式（探针/日志用）。
QString edgeName(Edge edge);

/// 面板信息（从 D-Bus 读来的真几何）。
struct Panel {
    bool valid = false; ///< 服务在不在、值读没读到
    QRect rect;         ///< 面板在屏幕坐标系里的矩形
    Edge edge = Edge::Unknown;

    bool isEmpty() const { return !valid || rect.isEmpty(); }
};

/// 屏幕矩形 → **扣掉面板**后的可用区。
///
/// ⚠ 扣的是**面板自己报的那块**，不是「屏幕边缘那条」——面板可以是浮动的
///   （贴着边但不占满），按边宽猜会多扣或少扣。
QRect usableArea(const QRect &screen, const Panel &panel);

/// QPA 推算的可用区 + 面板真几何 ⇒ 修正后的可用区。
///
/// ⚠ **为什么要「取交」而不是直接用面板算的**：
///   · X11 下 QPA 的 availableGeometry **已经**扣掉面板 ⇒ 两者一致，取交不变；
///   · Wayland 下 QPA **未必**扣（Qt 的 Wayland 插件没有「工作区」概念）
///     ⇒ 用面板真几何补上；
///   · 面板不在这块屏上（多屏 + 面板只在主屏）⇒ 不动。
QRect effectiveAvailable(const QRect &qpaAvailable, const QRect &screen, const Panel &panel);

} // namespace PanelGeometry
