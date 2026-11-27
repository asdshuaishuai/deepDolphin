// VDivider.h — 竖分隔线（**真线**：1 逻辑像素宽）。
//
// 【为什么不用文字当分隔线】—— 批 AW 实测（`/tmp/aw-probe2.cpp` 的结论照抄）：
//   旧写法 `QLabel(QStringLiteral("|"))` 的 sizeHint = **4 × 18 逻辑像素**
//   ⇒ ① 宽 4px（QLabel 带文本边距）而不是 1px ⇒ 分隔线离两侧按钮更远；
//      ② 高 18px（字体高度）而不是 14px ⇒ 与旁边按钮不对齐；
//      ③ 它是**字形** ⇒ 随字体/字号缩放变形，HiDPI dpr=2 时实测占 **8 × 36 物理像素**；
//      ④ 颜色用 QSS 写死 ⇒ 是**构建时快照** ⇒ 切主题后不更新。
//   ⇒ 四个问题都出在「用文字冒充线」上 ⇒ 换成自绘的真线。
//
// 【⚠ 为什么不用 QFrame::VLine】—— 同样实测：
//   `QFrame::VLine` + `QFrame::Plain` 画出来的是 **`QPalette::Text` 色**（实测 #ff000000），
//   **不是** `QPalette::Mid` ⇒ 深色主题下是一条**看不见的黑线**。
//   ⇒ 只能自绘，颜色取 `DS::surfaceBorder()`（= 调色板 Mid 口径，与 DTK 同档）。
//
// 【对位】mac 侧 `DetailViews.swift` 用 SwiftUI 原生 `Divider().frame(height: 14)`
//   ⇒ 1pt 宽、限高 14 的真线 ⇒ 本组件逐条对位（宽 1、高 `DS::Height::divider`）。
//
// 【无 Q_OBJECT】：纯呈现。
#pragma once
#include "../DesignTokens.h"
#include <QEvent>
#include <QPainter>
#include <QWidget>

class VDivider : public QWidget {
public:
    explicit VDivider(QWidget *parent = nullptr)
        : QWidget(parent)
    {
        // 宽 1 **逻辑**像素（dpr=2 时由 Qt 放大成 2 物理像素 ⇒ 真线也是真线）
        setFixedWidth(1);
        setFixedHeight(DS::Height::divider);
    }

protected:
    void paintEvent(QPaintEvent *event) override
    {
        Q_UNUSED(event);
        QPainter p(this);
        // ⚠ **不开抗锯齿**：1px 线开了 AA 边缘会半透明（看着像灰边而不是线）。
        //   （StatusDot 那种圆点要 AA，这里是直线，不要。）
        p.setPen(Qt::NoPen);
        // ⚠ **每次绘制都重取 token**：主题切换后重绘就能拿到新色，
        //   不用把颜色缓存成构建时快照（那正是旧写法 QSS 的毛病）。
        p.setBrush(DS::surfaceBorder());
        p.drawRect(0, 0, 1, height());
    }

    void changeEvent(QEvent *event) override
    {
        QWidget::changeEvent(event);
        // 主题/调色板变了 ⇒ 重绘（paintEvent 会重取 DS token）
        if (event->type() == QEvent::ThemeChange || event->type() == QEvent::PaletteChange)
            update();
    }
};
