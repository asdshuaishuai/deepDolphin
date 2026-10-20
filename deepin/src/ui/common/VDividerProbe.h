// VDividerProbe.h — 分隔线的**无头行为探针**（批 AW）。
//
// 【为什么要有这一门】
//   · 详情页**不在快照矩阵里**（快照拍 dashboard / board / milestones / setupguide）
//     ⇒ 快照**抓不到**分隔线的几何 ⇒ 必须另有判据，否则这次修复等于没门。
//   · ⚠ **为什么不能塞进 selfcheck**：`--selfcheck` 分支在 **GUI 应用构造之前**就 return
//     ⇒ 那个模式下**没有 QApplication** ⇒ 建不了 QWidget ⇒ 建 QWidget 会崩。
//     ⇒ 探针必须**自己构造 DApplication**（与 `--docs-lang-probe` 同款做法）。
//   · ⚠ 静态门（源码扫描）能证明「代码里写了 `new VDivider(...)`」，
//     但**证明不了**「画出来真的只有 1 像素宽、且颜色是 DS token」⇒ 这一门**真渲染**一次。
//
// 【报什么】一行一个 key=value（机器格式**归本文件**，组件里不留字面量）：
//   width / height   —— 逻辑尺寸
//   dpr              —— 渲染时的设备像素比
//   inkWidth         —— **有墨迹的列数**（物理像素）⇒ 抗锯齿/写宽都会让它变
//   inkHeight        —— 有墨迹的行数（物理像素）
//   inkColor         —— 实际画出来的颜色
//   tokenColor       —— 同一时刻 `DS::surfaceBorder()` 的值
//   opaque           —— 墨迹像素是否**全不透明**（开了抗锯齿就会有半透明边缘）
//
// 【用法的关键】
//   inkWidth / inkHeight 是**物理**像素 ⇒ 断言必须按 dpr 换算
//   （`inkWidth == dpr` ⇔ 恰好 1 **逻辑**像素宽）。
#pragma once
#include "VDivider.h"
#include <QGuiApplication>
#include <QImage>
#include <QPixmap>
#include <QScreen>
#include <QString>

inline QString dividerProbeReport()
{
    VDivider d;
    d.show();

    const qreal dpr = qApp->primaryScreen() ? qApp->primaryScreen()->devicePixelRatio() : 1.0;
    // ⚠ **按 dpr 放大 pixmap**（批 AP 纪律）：不放大 ⇒ 量到的是逻辑像素不是物理像素
    //   ⇒ dpr=2 时会把「2 物理像素的线」误判成「1 物理像素」。
    QPixmap pm(qMax(1, qRound(d.width() * dpr)), qMax(1, qRound(d.height() * dpr)));
    pm.setDevicePixelRatio(dpr);
    pm.fill(Qt::transparent);
    d.render(&pm);
    const QImage img = pm.toImage();

    int minX = img.width(), maxX = -1, minY = img.height(), maxY = -1;
    QColor ink;
    bool allOpaque = true;
    for (int y = 0; y < img.height(); ++y) {
        for (int x = 0; x < img.width(); ++x) {
            const QColor c = img.pixelColor(x, y);
            if (c.alpha() <= 0)
                continue;
            if (c.alpha() != 255)
                allOpaque = false;
            if (!ink.isValid())
                ink = c;
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
        }
    }
    const int inkW = (maxX < 0) ? 0 : (maxX - minX + 1);
    const int inkH = (maxY < 0) ? 0 : (maxY - minY + 1);

    return QStringLiteral(
               "width=%1\n"
               "height=%2\n"
               "dpr=%3\n"
               "inkWidth=%4\n"
               "inkHeight=%5\n"
               "inkColor=%6\n"
               "tokenColor=%7\n"
               "opaque=%8\n")
        .arg(d.width())
        .arg(d.height())
        .arg(dpr)
        .arg(inkW)
        .arg(inkH)
        .arg(ink.isValid() ? ink.name(QColor::HexArgb) : QStringLiteral("none"))
        .arg(DS::surfaceBorder().name(QColor::HexArgb))
        .arg(allOpaque ? 1 : 0);
}
